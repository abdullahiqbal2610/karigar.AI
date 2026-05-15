# Karigar.AI

[![Python](https://img.shields.io/badge/Python-3.x-3776AB?logo=python&logoColor=white)](https://www.python.org/)
[![Flutter](https://img.shields.io/badge/Flutter-Mobile%20App-02569B?logo=flutter&logoColor=white)](https://flutter.dev/)
[![Node.js](https://img.shields.io/badge/Node.js-Backend-339933?logo=node.js&logoColor=white)](https://nodejs.org/)

An intelligent, multimodal home-services marketplace built for Pakistan’s informal economy.

Karigar.AI goes beyond rigid dropdown menus by letting users request services naturally in **Roman Urdu**, **Urdu**, or **English** using **text**, **voice**, or **images**.  
The platform then translates messy real-world input into structured intent, finds the optimal technician, manages availability, and coordinates the booking automatically.

---

## Features

- **Multilingual Understanding**  
  Supports Roman Urdu, Urdu script, English, and mixed language input.

- **Multimodal Service Requests**  
  Users can place requests through text, voice-to-text (Flutter), or Image uploads (damage/context-aware intent extraction).

- **Multi-Agent Architecture**  
  A pipeline of three distinct AI agents working together to fulfill requests:
  - **Agent 1 (Intent Extractor)**: Converts natural language into structured JSON, using system dates to parse exact `target_date` and `target_time_slot`.
  - **Agent 2 (Intelligent Matchmaker)**: Filters the database by skill and real-time availability, computes Haversine distances to the user's location, and uses an LLM to select the optimal technician based on urgency and budget.
  - **Agent 3 (Coordinator)**: Interacts with the user to confirm the booking, handles negotiations/rejections (e.g., "I want someone cheaper"), updates the `appointments_ledger`, and dispatches mock SMS notifications to the technician.

- **Real-World Constraints**  
  Technicians are strictly limited to a maximum of 2 bookings per day via the `appointments_ledger.json` to reflect realistic scheduling limitations.

---

## Architecture Pipeline

Karigar.AI is organized as a modular, agent-driven system:

### 1) Multimodal Intent Extractor (Agent 1)
- Uses **Gemini 2.5 Flash** via an OpenAI-compatible REST API.
- Parses colloquial, noisy user requests into clean structured JSON.
- Incorporates visual signals from uploaded images.

### 2) Intelligent Matchmaker (Agent 2)
- **Deterministic Filtering**: Checks `karigars_db.json` (120+ profiles across Lahore/Islamabad) for required skills and filters out fully-booked technicians using `appointments_ledger.json`.
- **AI Decision Engine**: Weighs distance, technician rating, and user tier preferences to generate a "Glass Box" reasoning for its choice.

### 3) Customer Coordinator (Agent 3)
- NLP-driven interactive loop that determines user sentiment (ACCEPTED, REJECTED, NEGOTIATING).
- Automatically adjusts matching criteria (e.g., downgrading to "Budget" tier) if the user rejects a quote.
- Triggers outbound (mock) SMS to the Karigar upon confirmation.

### 4) Backend API & Frontend (WIP)
- **Backend (Node.js)**: Handles socket communication and orchestration.
- **Frontend (Flutter)**: Native mobile app with GPS fallback capabilities for seamless location tracking.

---

## Data Contract (Extracted Intent JSON)

```json
{
  "service_type": "AC Gas Leak Repair",
  "service_details": "Gas leak near outdoor unit copper joint",
  "location": "DHA Phase 5 Lahore",
  "raw_time": "kal subah",
  "target_date": "2026-05-16",
  "target_time_slot": "Morning",
  "urgency": "High",
  "tier": "Budget",
  "raw_language": "Roman Urdu"
}
```

---

## Installation

### Prerequisites

- Python 3.x
- Node.js (LTS recommended)
- Flutter SDK

### 1) Clone Repository

```bash
git clone https://github.com/abdullahiqbal2610/karigar.AI.git
cd karigar.AI
```

### 2) AI Agent Setup (Python)

```bash
cd ai_agents
python -m venv .venv
source .venv/bin/activate
pip install httpx python-dotenv
```

Create a `.env` file in the `ai_agents` directory:

```bash
LLM_API_KEY="your_api_key_here"
LLM_BASE_URL="https://generativelanguage.googleapis.com/v1beta/openai"
LLM_MODEL="gemini-2.5-flash"
```

To run the end-to-end test loop:
```bash
python ai_agents/coordinator.py
```

### 3) Backend & Mobile Setup (WIP)
Refer to the respective folders for `Node.js` and `Flutter` initialization instructions.

---

## Repository Structure

```text
karigar.AI/
├── ai_agents/
│   ├── .env.example
│   ├── intent_extractor.py       # Agent 1
│   ├── matchmaker.py             # Agent 2
│   ├── coordinator.py            # Agent 3
│   ├── karigars_db.json          # 120-profile database
│   └── appointments_ledger.json  # Booking tracker
├── backend/
│   └── README.md
└── mobile_app/
    └── README.md
```

---

## Team

- Muhammad Abdullah Iqbal (AI Lead)
- Bilal Ahmad khan
- Junaid Muhammad
- Ahmad Muaz Asad
