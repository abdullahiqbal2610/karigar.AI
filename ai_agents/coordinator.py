"""
coordinator.py
==============
Agent 3 — Karigar Coordinator.

Takes the matched technician from Agent 2 and talks to the user to confirm.
If accepted, records the appointment in `appointments_ledger.json` and 
sends a Mock SMS to the Karigar.
"""

import json
import os
import sys
from pathlib import Path
from datetime import datetime
from typing import Any

import httpx
from dotenv import load_dotenv

# Re-use extract logic
from matchmaker import _extract_json_from_response, _build_headers
from intent_extractor import extract_intent
from matchmaker import find_best_match

load_dotenv()

LEDGER_PATH = Path(__file__).parent / "appointments_ledger.json"
DEFAULT_BASE_URL = "https://generativelanguage.googleapis.com/v1beta/openai"
DEFAULT_MODEL = "gemini-2.5-flash"

COORDINATOR_PROMPT = """\
You are Agent 3, the Customer Coordinator for Karigar.AI.
The user was just presented with a technician match for their home service request.

You will receive:
1. The matched karigar's info.
2. The user's reply.

Your job is to determine if the user ACCEPTED the match, REJECTED it, or is ASKING FOR CHANGES.

Return strictly raw JSON (no markdown fences):
{
  "status": "ACCEPTED" | "REJECTED" | "NEGOTIATING",
  "user_sentiment": "<short summary of what the user wants>"
}
"""

def register_booking(karigar_id: str, date: str, time_slot: str) -> None:
    """Save the booking to the ledger."""
    ledger = []
    if LEDGER_PATH.exists():
        with open(LEDGER_PATH, "r", encoding="utf-8") as f:
            try:
                ledger = json.load(f)
            except json.JSONDecodeError:
                pass
    
    ledger.append({
        "karigar_id": karigar_id,
        "date": date,
        "time_slot": time_slot,
        "booked_at": datetime.now().isoformat()
    })
    
    with open(LEDGER_PATH, "w", encoding="utf-8") as f:
        json.dump(ledger, f, indent=2)

def notify_karigar(karigar: dict, intent: dict) -> None:
    """Mock sending an SMS to the technician."""
    print(f"\n[📱 MOCK SMS OUTBOUND TO {karigar.get('phone_number')}]")
    print("-" * 50)
    print(f"Naya Kaam! {intent.get('service_type')} at {intent.get('location')}.")
    print(f"Date: {intent.get('target_date')} | Slot: {intent.get('target_time_slot')}")
    print(f"Details: {intent.get('service_details')}")
    print("-" * 50)

def coordinate_booking(intent: dict, match: dict) -> bool:
    """Interact with the user to finalize the booking."""
    print("\n" + "=" * 60)
    print(" 🤖 AGENT 3 (COORDINATOR)")
    print("=" * 60)

    if not match.get("selected_karigar_id"):
        print("Sorry, we couldn't find a matching technician for your request.")
        return False

    k = match["karigar_profile"]
    
    print(f"\nMain ne {k['name']} ({k['rating']}★) ko dhoond liya hai.")
    print(f"Wo {match['distance_km']} km door hai ({k['tier']} tier).")
    print(f"Timing: {intent.get('target_date')} ({intent.get('target_time_slot')})")
    
    reply = input("\n> Shall I confirm this booking? (Yes / No / Need cheaper): ")
    
    # Use LLM to parse intent of reply
    api_key = os.getenv("LLM_API_KEY")
    base_url = os.getenv("LLM_BASE_URL", DEFAULT_BASE_URL).rstrip("/")
    model = os.getenv("LLM_MODEL", DEFAULT_MODEL)
    
    payload = {
        "model": model,
        "temperature": 0.0,
        "messages": [
            {"role": "system", "content": COORDINATOR_PROMPT},
            {"role": "user", "content": f"Match info: {k['name']}, {k['tier']} tier.\nUser reply: {reply}"}
        ]
    }
    
    with httpx.Client() as client:
        resp = client.post(f"{base_url}/chat/completions", headers=_build_headers(api_key), json=payload)
        resp.raise_for_status()
        
    raw = resp.json()["choices"][0]["message"]["content"]
    decision = _extract_json_from_response(raw)
    
    if decision["status"] == "ACCEPTED":
        print("\n✅ Awesome! Confirming your booking now...")
        register_booking(k["id"], intent.get("target_date"), intent.get("target_time_slot"))
        notify_karigar(k, intent)
        return "ACCEPTED", decision["user_sentiment"]
    else:
        print(f"\n❌ Booking not confirmed. User sentiment: {decision['user_sentiment']}")
        return decision["status"], decision["user_sentiment"]

if __name__ == "__main__":
    # Full End-to-End Test Loop
    print("\n" + "*" * 60)
    print(" 🏠 KARIGAR.AI END-TO-END WORKFLOW TEST")
    print("*" * 60)
    
    user_req = input("\nDescribe your problem: ")
    if not user_req:
        user_req = "Bhai kal DHA Phase 5 mein AC ki gas leak theek karni hai, premium banda laoo"
        print(f"Using default: {user_req}")
        
    print("\n[Agent 1 is extracting intent...]")
    intent = extract_intent(user_req)
    
    rejected_ids = []
    
    while True:
        print("\n[Agent 2 is finding the best match...]")
        try:
            match = find_best_match(intent, rejected_ids=rejected_ids)
            
            # If no matches are found at all
            if not match.get("selected_karigar_id"):
                print("\n❌ Sorry, we have completely run out of available technicians matching your criteria in this area.")
                break
                
            status, sentiment = coordinate_booking(intent, match)
            
            if status == "ACCEPTED":
                break
                
            elif status == "REJECTED" or status == "NEGOTIATING":
                # Add the rejected technician to the blacklist
                current_id = match["karigar_profile"]["id"]
                rejected_ids.append(current_id)
                print(f"\n[System] Okay, we will exclude {match['karigar_profile']['name']} and try again.")
                
                # If they explicitly ask for cheaper, update the intent constraints!
                if "cheaper" in sentiment.lower() or "sasta" in sentiment.lower(): 
                    print("[System] Adjusting search criteria to strictly match Budget tier...")
                    intent["tier"] = "Budget"

        except Exception as e:
            print(f"Error during match/coordination: {e}")
            break
