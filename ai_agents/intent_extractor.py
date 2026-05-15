"""
intent_extractor.py
====================
Parses natural-language home-service requests (Roman Urdu / Urdu / English)
into a structured JSON intent using the Google Gemini API.

Environment variables
---------------------
GEMINI_API_KEY   – Your Google AI Studio API key.
GEMINI_MODEL     – Model identifier to use.
                   Defaults to "gemini-2.5-flash"
"""

from __future__ import annotations

import json
import os
import re
import logging
from typing import Any


# ── Logging setup ────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(name)s  %(message)s",
)
logger = logging.getLogger("intent_extractor")

# ── Gemini defaults ──────────────────────────────────────────────────────────
DEFAULT_MODEL = "gemini-2.5-flash"
DEFAULT_TEMPERATURE = 0.0          # deterministic extraction

# ── System prompt ────────────────────────────────────────────────────────────
SYSTEM_PROMPT = """\
You are **Karigar Intent Parser**, an expert NLP module embedded inside a \
Pakistani home-services marketplace called *Karigar.AI*.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ROLE & OBJECTIVE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Your ONLY job is to read a single user message that describes a home-service \
need and return a **strictly valid JSON object** (no markdown, no explanation, \
no wrapping) with the following seven keys:

| Key             | Type            | Description |
|-----------------|-----------------|-------------|
| service_type    | string or null  | The exact type of service requested. Normalise to a concise English label \
(e.g. "AC Gas Leak Repair", "Plumbing", "Electrician", "House Cleaning", \
"Painter", "Carpenter", "Pest Control", "Appliance Repair", "Geyser Repair", \
"UPS / Inverter Repair", "CCTV Installation", etc.). Use null only when \
absolutely no service can be inferred. |
| service_details | string or null  | Any additional detail the user gave about the problem — e.g. "gas leak", \
"tap is dripping", "short circuit in kitchen". Keep it short but preserve \
the user's specifics. null if none. |
| location        | string or null  | The geographical location or area mentioned. Preserve the user's own \
wording but capitalise it consistently (e.g. "DHA Phase 5", "Gulshan-e-Iqbal \
Block 13", "F-8 Islamabad"). null if no location mentioned. |
| time            | string or null  | When the user wants the service. Convert colloquial references to a clear \
phrase: "kal subah" → "Tomorrow Morning", "aaj raat" → "Tonight", \
"abhi" / "foran" → "Immediately", "parson" → "Day After Tomorrow". \
If a specific date/day is given, keep it. null if not mentioned. |
| urgency         | "High" \\| "Medium" \\| "Low" | Infer from the user's tone, punctuation, \
and word choice. Indicators: \
**High** → words like "foran", "abhi", "emergency", "jaldi", "urgent", \
excessive punctuation (!!!, ???), all-caps, leak/short-circuit/flooding type \
issues. \
**Medium** → a specific near-future time ("kal subah", "tonight"), moderate \
language. \
**Low** → vague timing ("kisi din", "jab time mile", "next week"), relaxed \
tone. \
Default to "Medium" if uncertain. |
| tier            | "Budget" \\| "Premium" \\| "Any" | Infer from the user's language. \
**Budget** → "sasta", "kam rate", "budget", "reasonable", "cheap", \
"paisa bachao". \
**Premium** → "best", "top", "expert", "branded", "premium", \
"experienced", "trusted". \
**Any** → no cost preference expressed. \
Default to "Any" if uncertain. |
| raw_language    | "Roman Urdu" \\| "Urdu" \\| "English" \\| "Mixed" | The dominant \
language/script the user wrote in. "Mixed" if heavily code-switched. |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
HARD RULES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. Return **ONLY** the JSON object — no markdown fences, no commentary, no \
   trailing text.  The very first character of your response must be `{` and \
   the very last must be `}`.
2. All seven keys must ALWAYS be present.  Use `null` (JSON null, not the \
   string "null") for any field you truly cannot determine.
3. Do NOT hallucinate details.  If the user says nothing about timing, set \
   `time` to null — do NOT guess "Morning" or "ASAP".
4. For `service_type`, prefer the most specific label possible.  \
   "AC Gas Leak Repair" is better than "AC Repair" when the user \
   explicitly says "gas leak".
5. Understand Pakistani colloquialisms, Roman Urdu transliteration \
   variations, and Urdu script equally well.  Examples: \
   - "bijli ka kaam" → "Electrician" \
   - "pani ki tanki saaf" → "Water Tank Cleaning" \
   - "kapray ki almari banana hai" → "Carpenter" \
   - "pest spray karwana" → "Pest Control" \
   - "geyser phat gaya" → "Geyser Repair" (urgency likely High)
6. `urgency` and `tier` must NEVER be null — always pick one of the \
   allowed enum values.
7. If the entire message is unintelligible or completely unrelated to home \
   services, return all nullable fields as null, set urgency to "Medium", \
   tier to "Any", and raw_language to your best guess.
"""


def _extract_json_from_response(raw_text: str) -> dict[str, Any]:
    """
    Robustly extract a JSON object from the LLM's response text.

    Even though the system prompt demands raw JSON, some models wrap the
    output in ```json ... ``` fences.  This helper strips those if present,
    then parses the JSON.
    """
    text = raw_text.strip()

    # Strip optional markdown code fences
    fence_pattern = re.compile(
        r"^```(?:json)?\s*\n?(.*?)\n?\s*```$", re.DOTALL
    )
    match = fence_pattern.match(text)
    if match:
        text = match.group(1).strip()

    # Fallback: grab the first { ... } block
    if not text.startswith("{"):
        brace_match = re.search(r"\{.*\}", text, re.DOTALL)
        if brace_match:
            text = brace_match.group(0)

    try:
        return json.loads(text)
    except json.JSONDecodeError as exc:
        logger.error("Failed to parse LLM response as JSON:\n%s", raw_text)
        raise ValueError(
            f"LLM did not return valid JSON. Raw response:\n{raw_text}"
        ) from exc


# ── Primary public function ──────────────────────────────────────────────────

def extract_intent(
    user_message: str,
    *,
    api_key: str | None = None,
    model: str | None = None,
    temperature: float = DEFAULT_TEMPERATURE,
) -> dict[str, Any]:
    """
    Send a natural-language home-service request to Google Gemini and return
    structured intent fields.

    Parameters
    ----------
    user_message : str
        The raw user query (Roman Urdu, Urdu, English, or mixed).
    api_key : str, optional
        Google AI Studio API key.  Falls back to ``GEMINI_API_KEY`` env var.
    model : str, optional
        Gemini model identifier.  Falls back to ``GEMINI_MODEL`` env var,
        then to ``"gemini-2.5-flash"``.
    temperature : float
        Sampling temperature.  Defaults to 0.0 for deterministic output.

    Returns
    -------
    dict
        A dictionary with keys: ``service_type``, ``service_details``,
        ``location``, ``time``, ``urgency``, ``tier``, ``raw_language``.

    Raises
    ------
    google.api_core.exceptions.GoogleAPIError
        If the Gemini API returns an error.
    ValueError
        If the response cannot be parsed as valid JSON.
    """

    # ── Resolve configuration ────────────────────────────────────────────
    api_key = api_key or os.getenv("GEMINI_API_KEY")
    if not api_key:
        raise ValueError(
            "No API key provided. Either pass `api_key=` or set the "
            "GEMINI_API_KEY environment variable."
        )

    model_name = model or os.getenv("GEMINI_MODEL", DEFAULT_MODEL)

    # ── Configure the SDK ────────────────────────────────────────────────

    gemini_model = genai.GenerativeModel(
        model_name=model_name,
        system_instruction=SYSTEM_PROMPT,
        generation_config=genai.types.GenerationConfig(
            temperature=temperature,
            response_mime_type="application/json",   # enforce JSON output
        ),
    )

    logger.info("Calling Gemini  model=%s  temp=%.1f", model_name, temperature)
    logger.debug("User message: %s", user_message)

    # ── Call the API ─────────────────────────────────────────────────────
    response = gemini_model.generate_content(user_message)
    raw_text = response.text

    logger.debug("Raw Gemini response:\n%s", raw_text)

    intent = _extract_json_from_response(raw_text)

    # ── Sanity-check: ensure all expected keys are present ───────────────
    expected_keys = {
        "service_type", "service_details", "location",
        "time", "urgency", "tier", "raw_language",
    }
    missing = expected_keys - intent.keys()
    if missing:
        logger.warning("LLM response missing keys: %s — backfilling with null", missing)
        for key in missing:
            intent[key] = None

    # ── Enforce enum constraints ─────────────────────────────────────────
    if intent.get("urgency") not in ("High", "Medium", "Low"):
        logger.warning("Invalid urgency '%s' — defaulting to 'Medium'", intent.get("urgency"))
        intent["urgency"] = "Medium"

    if intent.get("tier") not in ("Budget", "Premium", "Any"):
        logger.warning("Invalid tier '%s' — defaulting to 'Any'", intent.get("tier"))
        intent["tier"] = "Any"

    return intent


# ── CLI / quick-test block ───────────────────────────────────────────────────

if __name__ == "__main__":
    test_input = (
        "Bhai DHA Phase 5 mein kal subah AC ki gas leak theek karwani hai, "
        "koi sasta banda bhejna yaar."
    )

    print("=" * 72)
    print("  Karigar.AI — Intent Extractor  (test run)")
    print("=" * 72)
    print(f"\n📝  Input:\n    \"{test_input}\"\n")

    try:
        result = extract_intent(test_input)
        print("✅  Extracted Intent:\n")
        print(json.dumps(result, indent=2, ensure_ascii=False))
    except Exception as exc:
        logger.exception("Intent extraction failed")
        print(f"\n❌  Error: {exc}")

    # ── Show what the *expected* output should look like ──────────────────
    expected = {
        "service_type": "AC Gas Leak Repair",
        "service_details": "AC gas leak fix",
        "location": "DHA Phase 5",
        "time": "Tomorrow Morning",
        "urgency": "Medium",
        "tier": "Budget",
        "raw_language": "Roman Urdu",
    }

    print("\n" + "-" * 72)
    print("📋  Expected output (for reference):\n")
    print(json.dumps(expected, indent=2, ensure_ascii=False))
    print()
