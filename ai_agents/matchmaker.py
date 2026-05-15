"""
matchmaker.py
==============
Agent 2 — Karigar Matchmaker.

Takes the structured JSON intent produced by ``intent_extractor.py``
(Agent 1) and finds the single best technician from ``karigars_db.json``.

The matching happens in two stages:
    A. **Deterministic Filter** — skill match + haversine distance calc.
    B. **AI Decision** — an LLM picks the winner from the shortlist,
       balancing distance, rating, and price tier against the user's
       urgency and budget preference.  It also returns a short "Glass Box"
       explanation so the user knows *why* this technician was chosen.

Environment variables (same as intent_extractor.py)
----------------------------------------------------
LLM_API_KEY      – Bearer token / API key.
LLM_BASE_URL     – Base URL of the OpenAI-compatible endpoint.
                   Defaults to Google Gemini's bridge.
LLM_MODEL        – Model identifier.  Defaults to "gemini-2.5-flash".
"""

from __future__ import annotations

import json
import math
import os
import re
import logging
from pathlib import Path
from typing import Any

import httpx
from dotenv import load_dotenv

# Load environment variables from .env file if it exists
load_dotenv()

# ── Logging ──────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(name)s  %(message)s",
)
logger = logging.getLogger("matchmaker")

# ── LLM defaults (mirrors intent_extractor.py) ──────────────────────────────
DEFAULT_BASE_URL = "https://generativelanguage.googleapis.com/v1beta/openai"
DEFAULT_MODEL = "gemini-2.5-flash"

# ── Paths ───────────────────────────────────────────────────────────────────
DB_PATH = Path(__file__).parent / "karigars_db.json"
LEDGER_PATH = Path(__file__).parent / "appointments_ledger.json"

# ── Hardcoded user-location coordinates for testing ─────────────────────────
# In production this would come from the mobile app's GPS or a geocoding API.
USER_COORDINATES: dict[str, dict[str, float]] = {
    # ── Lahore (35 areas) ────────────────────────────────────────────────
    "Allama Iqbal Town":               {"lat": 31.467, "lng": 74.281},
    "Askari 10":                       {"lat": 31.439, "lng": 74.248},
    "Askari 11":                       {"lat": 31.425, "lng": 74.237},
    "Bahria Town Lahore":              {"lat": 31.366, "lng": 74.182},
    "Cantt":                           {"lat": 31.531, "lng": 74.368},
    "Cavalry Ground":                  {"lat": 31.5165, "lng": 74.358},
    "DHA Phase 5":                     {"lat": 31.4697, "lng": 74.3762},
    "DHA Phase 6":                     {"lat": 31.4612, "lng": 74.389},
    "DHA Phase 8":                     {"lat": 31.454, "lng": 74.405},
    "EME Society":                     {"lat": 31.448, "lng": 74.276},
    "Faisal Town":                     {"lat": 31.4785, "lng": 74.3105},
    "Garden Town":                     {"lat": 31.5074, "lng": 74.334},
    "Green Town":                      {"lat": 31.475, "lng": 74.265},
    "Gulberg III":                     {"lat": 31.5204, "lng": 74.3487},
    "Gulshan-e-Ravi":                  {"lat": 31.561, "lng": 74.352},
    "Ichhra":                          {"lat": 31.526, "lng": 74.329},
    "Iqbal Town":                      {"lat": 31.4687, "lng": 74.282},
    "Johar Town":                      {"lat": 31.4622, "lng": 74.2955},
    "Lake City":                       {"lat": 31.387, "lng": 74.162},
    "Model Town":                      {"lat": 31.4804, "lng": 74.3239},
    "Mozang":                          {"lat": 31.549, "lng": 74.341},
    "Mughalpura":                      {"lat": 31.572, "lng": 74.365},
    "Muslim Town":                     {"lat": 31.5105, "lng": 74.3195},
    "Punjab Society":                  {"lat": 31.456, "lng": 74.29},
    "Sabzazar":                        {"lat": 31.487, "lng": 74.2747},
    "Samanabad":                       {"lat": 31.518, "lng": 74.31},
    "Shadman":                         {"lat": 31.538, "lng": 74.334},
    "Shahdara":                        {"lat": 31.595, "lng": 74.3014},
    "Sui Gas Housing":                 {"lat": 31.469, "lng": 74.3},
    "Taj Bagh":                        {"lat": 31.582, "lng": 74.339},
    "Thokar Niaz Baig":                {"lat": 31.453, "lng": 74.21},
    "Township":                        {"lat": 31.4505, "lng": 74.3095},
    "Valencia Town":                   {"lat": 31.431, "lng": 74.256},
    "Wahdat Road":                     {"lat": 31.493, "lng": 74.305},
    "Wapda Town":                      {"lat": 31.4535, "lng": 74.2648},
    # ── Islamabad / Rawalpindi (35 areas) ────────────────────────────────
    "Bahria Town Islamabad":           {"lat": 33.5215, "lng": 73.0913},
    "Bahria Town Phase 8 Rwp":         {"lat": 33.512, "lng": 73.08},
    "Blue Area":                       {"lat": 33.713, "lng": 73.061},
    "Chaklala Scheme 3":               {"lat": 33.608, "lng": 73.093},
    "DHA Phase 1 Islamabad":           {"lat": 33.545, "lng": 73.138},
    "DHA Phase 2 Islamabad":           {"lat": 33.531, "lng": 73.158},
    "E-7":                             {"lat": 33.741, "lng": 73.069},
    "E-11":                            {"lat": 33.7122, "lng": 72.984},
    "F-6":                             {"lat": 33.726, "lng": 73.068},
    "F-7":                             {"lat": 33.7194, "lng": 73.0585},
    "F-8":                             {"lat": 33.71, "lng": 73.0551},
    "F-10":                            {"lat": 33.698, "lng": 73.017},
    "F-11":                            {"lat": 33.693, "lng": 72.998},
    "G-6":                             {"lat": 33.729, "lng": 73.082},
    "G-7":                             {"lat": 33.71, "lng": 73.065},
    "G-8":                             {"lat": 33.699, "lng": 73.047},
    "G-9":                             {"lat": 33.6938, "lng": 73.03},
    "G-10":                            {"lat": 33.694, "lng": 73.014},
    "G-11":                            {"lat": 33.687, "lng": 73.001},
    "G-13":                            {"lat": 33.667, "lng": 72.978},
    "G-14":                            {"lat": 33.659, "lng": 72.962},
    "G-15":                            {"lat": 33.648, "lng": 72.943},
    "H-8":                             {"lat": 33.682, "lng": 73.058},
    "H-9":                             {"lat": 33.671, "lng": 73.043},
    "H-13":                            {"lat": 33.653, "lng": 72.972},
    "I-8":                             {"lat": 33.666, "lng": 73.072},
    "I-9":                             {"lat": 33.658, "lng": 73.048},
    "I-10":                            {"lat": 33.651, "lng": 73.021},
    "I-14":                            {"lat": 33.629, "lng": 72.964},
    "Kuri Road":                       {"lat": 33.605, "lng": 73.112},
    "PWD Housing Society":             {"lat": 33.574, "lng": 73.078},
    "Rawat":                           {"lat": 33.542, "lng": 73.168},
    "Satellite Town Rawalpindi":       {"lat": 33.615, "lng": 73.056},
    "Soan Garden":                     {"lat": 33.631, "lng": 73.055},
    "Tarnol":                          {"lat": 33.656, "lng": 72.945},
}

# ── LLM system prompt for the AI-decision step ──────────────────────────────
MATCHMAKER_PROMPT = """\
You are **Karigar Matchmaker**, the ranking engine inside a Pakistani \
home-services marketplace called *Karigar.AI*.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ROLE & OBJECTIVE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
You will receive:
1. A list of **shortlisted technicians** (already filtered by skill).  Each \
   entry includes: id, name, rating (1-5), tier ("Budget" or "Premium"), \
   distance_km (from the user), and skills.
2. The **user's preferences**: urgency ("High" / "Medium" / "Low") and \
   desired tier ("Budget" / "Premium" / "Any").

Your job is to pick the **single best technician** by balancing three factors:

| Factor       | Weight guidance |
|--------------|-----------------|
| **Distance** | Closer is better.  For "High" urgency, distance matters \
more — heavily penalise anyone > 10 km.  For "Low" urgency, distance is \
less critical. |
| **Rating**   | Higher is better.  A 4.5+ rating deserves a meaningful \
boost.  Below 3.5 is risky — avoid unless no alternative. |
| **Tier**     | If the user asked for "Budget", prefer Budget technicians \
(lower cost).  If "Premium", prefer Premium.  If "Any", treat tier as \
neutral. |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
OUTPUT FORMAT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Return **ONLY** a valid JSON object (no markdown fences, no commentary).  \
The very first character must be `{` and the very last must be `}`.

{
  "selected_karigar_id": "<id of the chosen technician>",
  "selected_karigar_name": "<name>",
  "reasoning": "<Exactly 2 sentences explaining why this technician was \
chosen over the others.  Mention distance, rating, and tier trade-offs.>"
}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
HARD RULES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. Keep the reasoning explicitly concise and under 30 words to prevent token cutoff. Return ONLY raw JSON.
2. You MUST pick exactly one technician.  Never return an empty selection.
3. If all candidates are roughly equal, prefer the one with the highest \
   rating as the tiebreaker.
"""


# ═════════════════════════════════════════════════════════════════════════════
# UTILITY FUNCTIONS
# ═════════════════════════════════════════════════════════════════════════════

def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """
    Calculate the great-circle distance between two points on Earth
    using the Haversine formula.

    Parameters
    ----------
    lat1, lon1 : float
        Latitude and longitude of point 1 in **decimal degrees**.
    lat2, lon2 : float
        Latitude and longitude of point 2 in **decimal degrees**.

    Returns
    -------
    float
        Distance in **kilometres**.
    """
    R = 6371.0  # Earth's mean radius in km

    φ1, φ2 = math.radians(lat1), math.radians(lat2)
    Δφ = math.radians(lat2 - lat1)
    Δλ = math.radians(lon2 - lon1)

    a = math.sin(Δφ / 2) ** 2 + math.cos(φ1) * math.cos(φ2) * math.sin(Δλ / 2) ** 2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

    return R * c


def _build_headers(api_key: str | None) -> dict[str, str]:
    """Construct HTTP headers for the chat-completion request."""
    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    return headers


def _extract_json_from_response(raw_text: str) -> dict[str, Any]:
    """Robustly extract a JSON object from the LLM response."""
    text = raw_text.strip()

    # Strip out markdown backticks and 'json' keyword
    text = re.sub(r"```json", "", text, flags=re.IGNORECASE)
    text = text.replace("```", "")
    text = text.strip()

    # Fallback: grab the { ... } block if there's still leading/trailing junk
    if not text.startswith("{") or not text.endswith("}"):
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


# ═════════════════════════════════════════════════════════════════════════════
# CORE MATCHING LOGIC
# ═════════════════════════════════════════════════════════════════════════════

def find_best_match(
    intent_json: dict[str, Any],
    *,
    rejected_ids: list[str] | None = None,
    api_key: str | None = None,
    base_url: str | None = None,
    model: str | None = None,
    timeout: float = 30.0,
) -> dict[str, Any]:
    """
    Given a parsed intent from Agent 1, find the best technician.

    Parameters
    ----------
    intent_json : dict
        The JSON output from ``extract_intent()`` — must contain at least
        ``service_type``, ``location``, ``urgency``, and ``tier``.
    api_key, base_url, model :
        LLM connection overrides (same as intent_extractor.py).
    timeout : float
        HTTP request timeout in seconds.

    Returns
    -------
    dict
        ``selected_karigar_id``, ``selected_karigar_name``, ``reasoning``,
        plus the full ``karigar_profile`` and ``distance_km``.
    """

    service_type = intent_json.get("service_type")
    location = intent_json.get("location")
    urgency = intent_json.get("urgency", "Medium")
    tier_pref = intent_json.get("tier", "Any")
    target_date = intent_json.get("target_date")

    if not service_type:
        raise ValueError("intent_json must contain a non-null 'service_type'.")

    # ── Load the technician database ─────────────────────────────────────
    with open(DB_PATH, "r", encoding="utf-8") as f:
        all_karigars: list[dict] = json.load(f)

    logger.info("Loaded %d technicians from %s", len(all_karigars), DB_PATH.name)

    # ══════════════════════════════════════════════════════════════════════
    # STEP A — Deterministic Filter
    # ══════════════════════════════════════════════════════════════════════

    # A1: Filter by skill match and rejected_ids
    rejected_ids = rejected_ids or []
    matched = [
        k for k in all_karigars
        if any(service_type.lower() in skill.lower() for skill in k["skills"])
        and k["id"] not in rejected_ids
    ]
    logger.info(
        "Skill filter: %d / %d technicians match '%s'",
        len(matched), len(all_karigars), service_type,
    )

    # A2: Filter by availability (max 2 bookings per day)
    if target_date:
        if LEDGER_PATH.exists():
            with open(LEDGER_PATH, "r", encoding="utf-8") as f:
                try:
                    ledger = json.load(f)
                except json.JSONDecodeError:
                    ledger = []
        else:
            ledger = []

        # Count bookings per karigar for the target date
        bookings_for_date = {}
        for appt in ledger:
            if appt.get("date") == target_date:
                kid = appt.get("karigar_id")
                bookings_for_date[kid] = bookings_for_date.get(kid, 0) + 1

        # Drop karigars with >= 2 bookings
        available_matched = []
        for k in matched:
            if bookings_for_date.get(k["id"], 0) < 2:
                available_matched.append(k)
        
        dropped = len(matched) - len(available_matched)
        matched = available_matched
        logger.info("Availability filter: %d dropped because they are fully booked on %s", dropped, target_date)

    if not matched:
        return {
            "selected_karigar_id": None,
            "selected_karigar_name": None,
            "reasoning": "No technician in the database has a matching skill.",
            "karigar_profile": None,
            "distance_km": None,
        }

    # A2: Calculate distance from user's location
    user_coords = USER_COORDINATES.get(location) if location else None

    for k in matched:
        if user_coords:
            k["distance_km"] = round(
                haversine_distance(
                    user_coords["lat"], user_coords["lng"],
                    k["coordinates"]["lat"], k["coordinates"]["lng"],
                ),
                2,
            )
        else:
            k["distance_km"] = None  # unknown — let the LLM deprioritise

    # Sort shortlist by distance (closest first) for readability
    matched.sort(key=lambda k: k["distance_km"] if k["distance_km"] is not None else 9999)

    logger.info("Shortlist (%d candidates):", len(matched))
    for k in matched:
        logger.info(
            "  • %s (%s)  |  %.1f★  |  %s  |  %s km  |  %s",
            k["name"], k.get("phone_number", "No Phone"), k["rating"], k["tier"],
            k["distance_km"], k["base_location_name"],
        )

    # ══════════════════════════════════════════════════════════════════════
    # STEP B — AI Decision via LLM
    # ══════════════════════════════════════════════════════════════════════

    # Build a compact summary for the LLM
    candidates_for_llm = [
        {
            "id": k["id"],
            "name": k["name"],
            "rating": k["rating"],
            "tier": k["tier"],
            "distance_km": k["distance_km"],
            "skills": k["skills"],
        }
        for k in matched
    ]

    user_prompt = json.dumps(
        {
            "user_urgency": urgency,
            "user_tier_preference": tier_pref,
            "candidates": candidates_for_llm,
        },
        indent=2,
        ensure_ascii=False,
    )

    # ── LLM call (identical pattern to intent_extractor.py) ──────────────
    api_key = api_key or os.getenv("LLM_API_KEY")
    if not api_key:
        raise ValueError(
            "No API key provided. Either pass `api_key=` or set the "
            "LLM_API_KEY environment variable."
        )

    base_url = (base_url or os.getenv("LLM_BASE_URL", DEFAULT_BASE_URL)).rstrip("/")
    model = model or os.getenv("LLM_MODEL", DEFAULT_MODEL)
    url = f"{base_url}/chat/completions"

    payload = {
        "model": model,
        "temperature": 0.0,
        "max_tokens": 2048,
        "messages": [
            {"role": "system", "content": MATCHMAKER_PROMPT},
            {"role": "user", "content": user_prompt},
        ],
    }

    logger.info("Calling LLM for ranking  model=%s  url=%s", model, url)

    with httpx.Client(timeout=timeout) as client:
        response = client.post(url, headers=_build_headers(api_key), json=payload)
        response.raise_for_status()

    body = response.json()
    raw_text = body["choices"][0]["message"]["content"]

    logger.debug("Raw LLM ranking response:\n%s", raw_text)

    decision = _extract_json_from_response(raw_text)

    # ── Attach the full karigar profile for downstream use ───────────────
    selected_id = decision.get("selected_karigar_id")
    selected_profile = next((k for k in matched if k["id"] == selected_id), None)

    decision["karigar_profile"] = selected_profile
    decision["distance_km"] = selected_profile["distance_km"] if selected_profile else None

    return decision


# ═════════════════════════════════════════════════════════════════════════════
# CLI / QUICK-TEST BLOCK
# ═════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":

    # Simulated output from Agent 1 (intent_extractor.py)
    agent1_output = {
        "service_type": "AC Gas Leak Repair",
        "service_details": "AC gas leak fix",
        "location": "Samanabad",
        "time": "Tomorrow Morning",
        "urgency": "Medium",
        "tier": "Budget",
        "raw_language": "Roman Urdu",
    }

    print("=" * 72)
    print("  Karigar.AI — Matchmaker Agent  (test run)")
    print("=" * 72)

    print("\n📥  Agent 1 Intent (input):\n")
    print(json.dumps(agent1_output, indent=2, ensure_ascii=False))

    print("\n" + "-" * 72)
    print("🔍  Running matchmaker...\n")

    try:
        result = find_best_match(agent1_output)

        print("✅  Best Match Found:\n")
        print(f"   🧑‍🔧  Name    : {result.get('selected_karigar_name')}")
        print(f"   🆔  ID      : {result.get('selected_karigar_id')}")
        print(f"   📍  Distance: {result.get('distance_km')} km")

        profile = result.get("karigar_profile")
        if profile:
            print(f"   ⭐  Rating  : {profile['rating']}")
            print(f"   💰  Tier    : {profile['tier']}")
            print(f"   🏠  Base    : {profile['base_location_name']}")

        print(f"\n   💬  Reasoning: {result.get('reasoning')}")

        print("\n" + "-" * 72)
        print("📋  Full LLM Decision JSON:\n")
        # Print without the large nested profile for clarity
        display = {k: v for k, v in result.items() if k != "karigar_profile"}
        print(json.dumps(display, indent=2, ensure_ascii=False))

    except Exception as exc:
        logger.exception("Matchmaker failed")
        print(f"\n❌  Error: {exc}")

    print()
