"""
intent_extractor.py
====================
Multimodal intent parser for home-service requests (Roman Urdu / Urdu /
English).  Accepts text and/or an image.  Uses any OpenAI-compatible
chat-completion endpoint via httpx (works with Gemini via OpenAI-compat
layer, OpenAI, Groq, Together, local Ollama, etc.).

Environment variables
---------------------
LLM_API_KEY      – Bearer token / API key for the LLM provider.
LLM_BASE_URL     – Base URL of the chat-completions endpoint.
                   Defaults to "https://generativelanguage.googleapis.com/v1beta/openai"
                   (Google Gemini OpenAI-compatible endpoint).
LLM_MODEL        – Model identifier to use.
                   Defaults to "gemini-2.5-flash"
"""

from __future__ import annotations

import json
import os
import re
import logging
from typing import Any

import httpx
from dotenv import load_dotenv

# Load environment variables from .env file if it exists
load_dotenv()

# ── Logging setup ────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(name)s  %(message)s",
)
logger = logging.getLogger("intent_extractor")

# ── LLM connection defaults ─────────────────────────────────────────────────
# Google Gemini's OpenAI-compatible endpoint
DEFAULT_BASE_URL = "https://generativelanguage.googleapis.com/v1beta/openai"
DEFAULT_MODEL = "gemini-2.5-flash"
DEFAULT_TEMPERATURE = 0.0          # deterministic extraction
DEFAULT_MAX_TOKENS = 512           # JSON output is compact

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

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
VISION / IMAGE ANALYSIS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
If an image is provided alongside the text message, you MUST analyse it to \
extract additional context that improves your response.  Specifically:
- **Identify the appliance / fixture**: brand name, model number, type \
  (e.g. "Haier 1.5-ton split AC", "Master geyser", "Philips ceiling fan").
- **Assess visible damage or symptoms**: rust, water stains, burn marks, \
  ice build-up, cracked pipes, sparking wires, pest droppings, etc.
- **Refine `service_type`**: use visual evidence to pick the most specific \
  label (e.g. if the image shows a compressor with frost → \
  "AC Compressor Repair" rather than generic "AC Repair").
- **Enrich `service_details`**: mention what you see — e.g. \
  "Visible refrigerant leak near the copper joint, corrosion on the \
  outdoor unit fins".
- **Adjust `urgency`**: if the image shows active flooding, sparking, or \
  fire damage, override urgency to "High" regardless of the text tone.
- If the image is irrelevant, blurry, or unrelated to home services, \
  ignore it and rely solely on the text.
"""


def _build_headers(api_key: str | None) -> dict[str, str]:
    """Construct HTTP headers for the chat-completion request."""
    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    return headers


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
    base64_image: str | None = None,
    api_key: str | None = None,
    base_url: str | None = None,
    model: str | None = None,
    temperature: float = DEFAULT_TEMPERATURE,
    max_tokens: int = DEFAULT_MAX_TOKENS,
    timeout: float = 30.0,
) -> dict[str, Any]:
    """
    Send a natural-language (and optionally visual) home-service request
    to an LLM and return structured intent fields.

    Parameters
    ----------
    user_message : str
        The raw user query (Roman Urdu, Urdu, English, or mixed).
    base64_image : str, optional
        A base64-encoded image string (JPEG / PNG / WebP).  When provided
        the payload switches to the OpenAI Vision message format so the
        model can analyse the photo for brands, damage, and symptoms.
    api_key : str, optional
        LLM provider API key.  Falls back to ``LLM_API_KEY`` env var.
    base_url : str, optional
        Root URL of the OpenAI-compatible API.
        Falls back to ``LLM_BASE_URL`` env var, then to Google Gemini's
        OpenAI-compatible endpoint.
    model : str, optional
        Model identifier.  Falls back to ``LLM_MODEL`` env var, then to
        ``"gemini-2.5-flash"``.
    temperature : float
        Sampling temperature.  Defaults to 0.0 for deterministic output.
    max_tokens : int
        Max tokens in the completion.  512 is plenty for the JSON payload.
    timeout : float
        HTTP request timeout in seconds.

    Returns
    -------
    dict
        A dictionary with keys: ``service_type``, ``service_details``,
        ``location``, ``time``, ``urgency``, ``tier``, ``raw_language``.

    Raises
    ------
    httpx.HTTPStatusError
        If the LLM API returns a non-2xx status code.
    ValueError
        If the response cannot be parsed as valid JSON.
    """

    # ── Resolve configuration ────────────────────────────────────────────
    api_key = api_key or os.getenv("LLM_API_KEY")
    if not api_key:
        raise ValueError(
            "No API key provided. Either pass `api_key=` or set the "
            "LLM_API_KEY environment variable."
        )

    base_url = (base_url or os.getenv("LLM_BASE_URL", DEFAULT_BASE_URL)).rstrip("/")
    model = model or os.getenv("LLM_MODEL", DEFAULT_MODEL)

    url = f"{base_url}/chat/completions"

    # ── Build the user message content ───────────────────────────────────
    # Text-only  → simple string  (saves tokens)
    # With image → OpenAI Vision array format
    if base64_image:
        user_content: str | list[dict] = [
            {"type": "text", "text": user_message},
            {
                "type": "image_url",
                "image_url": {
                    "url": f"data:image/jpeg;base64,{base64_image}",
                },
            },
        ]
        logger.info("Image attached — using multimodal Vision payload")
    else:
        user_content = user_message

    # ── Build the request payload ────────────────────────────────────────
    payload = {
        "model": model,
        "temperature": temperature,
        "max_tokens": max_tokens,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_content},
        ],
    }

    logger.info(
        "Calling LLM  model=%s  url=%s  temp=%.1f  vision=%s",
        model, url, temperature, bool(base64_image),
    )
    logger.debug("User message: %s", user_message)

    # ── Make the HTTP request ────────────────────────────────────────────
    with httpx.Client(timeout=timeout) as client:
        response = client.post(url, headers=_build_headers(api_key), json=payload)
        response.raise_for_status()

    body = response.json()
    raw_text = body["choices"][0]["message"]["content"]

    logger.debug("Raw LLM response:\n%s", raw_text)

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
    import base64
    from pathlib import Path

    test_input = (
        "Bhai DHA Phase 5 mein kal subah AC ki gas leak theek karwani hai, "
        "koi sasta banda bhejna yaar."
    )

    # ── Optional: load a real image for multimodal testing ────────────────
    # To test with an actual photo, place an image file path below.
    # Example:  TEST_IMAGE_PATH = r"C:\Users\abdul\Pictures\ac_leak.jpg"
    TEST_IMAGE_PATH: str | None = None  # ← set to a file path to enable

    test_image_b64: str | None = None
    if TEST_IMAGE_PATH and Path(TEST_IMAGE_PATH).is_file():
        raw_bytes = Path(TEST_IMAGE_PATH).read_bytes()
        test_image_b64 = base64.b64encode(raw_bytes).decode("utf-8")
        logger.info("Loaded test image: %s (%d bytes)", TEST_IMAGE_PATH, len(raw_bytes))

    print("=" * 72)
    print("  Karigar.AI — Intent Extractor  (test run)")
    print("=" * 72)
    print(f"\n📝  Input:\n    \"{test_input}\"")
    print(f"🖼️  Image: {'attached (' + TEST_IMAGE_PATH + ')' if test_image_b64 else 'none (text-only mode)'}\n")

    try:
        result = extract_intent(test_input, base64_image=test_image_b64)
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
    print("📋  Expected output (for reference — text-only mode):\n")
    print(json.dumps(expected, indent=2, ensure_ascii=False))
    print("\n💡  Tip: Set TEST_IMAGE_PATH above to test multimodal mode.")
    print()
