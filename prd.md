# Product Requirements Document: Karigar.AI Backend

## Project Context
Karigar.AI is an agentic AI system for Pakistan's informal economy. It matches users with service providers (plumbers, electricians, etc.) using natural language processing. The project is a MERN-style architecture, substituting MongoDB with mock JSON files for rapid hackathon prototyping. 

## System Architecture
* **Frontend:** Flutter mobile app (handles UI, voice-to-text, and GPS).
* **Backend:** Node.js/Express server with Socket.io (acts as the orchestrator and state manager).
* **AI Brain:** Python scripts running locally, executed via Node.js `child_process`.

## Backend Responsibilities
1. Accept incoming service requests from the Flutter app via a REST API endpoint.
2. Use Socket.io to emit real-time status updates back to the Flutter app while the AI is "thinking".
3. Spawn a Python child process to run `ai_agents/coordinator.py`, passing the user's prompt as an argument.
4. Capture the standard output (stdout) from the Python script, parse the resulting JSON, and return it to the frontend.
5. Manage state by reading and writing to `ai_agents/appointments_ledger.json` to enforce the constraint of a maximum of 2 bookings per technician per day.

## API Contracts
**Endpoint:** `POST /api/request-service`
**Request Payload:**
{
  "prompt": "Mujhe kal subah G-13 mein AC technician chahiye",
  "language": "Roman Urdu"
}

**Expected AI JSON Response:**
{
  "service_type": "AC Technician",
  "location": "G-13",
  "target_date": "2026-05-19",
  "target_time_slot": "Morning",
  "recommended_provider": "Ali AC Services",
  "status": "Booking Confirmed"
}