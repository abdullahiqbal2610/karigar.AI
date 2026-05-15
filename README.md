# Karigar.AI

[![Python](https://img.shields.io/badge/Python-3.x-3776AB?logo=python&logoColor=white)](https://www.python.org/)
[![Flutter](https://img.shields.io/badge/Flutter-Mobile%20App-02569B?logo=flutter&logoColor=white)](https://flutter.dev/)
[![Node.js](https://img.shields.io/badge/Node.js-Backend-339933?logo=node.js&logoColor=white)](https://nodejs.org/)

An intelligent, multimodal home-services marketplace built for Pakistan’s informal economy.

Karigar.AI goes beyond rigid dropdown menus by letting users request services naturally in **Roman Urdu**, **Urdu**, or **English** using **text**, **voice**, or **images**.  
The platform then translates messy real-world input into structured intent and routes it toward the right technician workflow.

---

## Features

- **Multilingual Understanding**  
  Supports Roman Urdu, Urdu script, English, and mixed language input.

- **Multimodal Service Requests**  
  Users can place requests through:
  - Text messages
  - Voice-to-text transcription (Flutter native support)
  - Image uploads (damage/context-aware intent extraction)

- **Smart Intent Extraction (Agent 1)**  
  Python-based AI agent that extracts structured fields:
  - `service_type`
  - `service_details`
  - `location`
  - `time`
  - `urgency` (High / Medium / Low)
  - `tier` (Budget / Premium / Any)
  - `raw_language`

- **Visual Damage Awareness**  
  Optional base64 image input is analyzed to identify visible faults like leaks, burn marks, corrosion, or electrical risk.

- **Intelligent Matchmaker (Agent 2 - WIP)**  
  Autonomous routing logic that aims to balance user urgency and budget preference, instead of only choosing by nearest location.

---

## Architecture

Karigar.AI is organized as a modular, agent-driven system:

### 1) Multimodal Intent Extractor (Agent 1) — Python
- Uses an LLM (**Gemini 2.5 Flash**) via an OpenAI-compatible REST API.
- Parses colloquial, noisy user requests into clean structured JSON.
- Incorporates visual signals from uploaded images when provided.

### 2) Intelligent Matchmaker (Agent 2) — WIP
- Autonomous decision layer for technician assignment.
- Weighs urgency and price sensitivity to improve service fit quality.

### 3) Backend API — Node.js
- Handles socket communication and orchestration.
- Routes request payloads between frontend clients and AI agents.

### 4) Frontend — Flutter Mobile App
- Native voice-to-text capture.
- Image capture/upload for multimodal requests.
- User-facing request flow for home services (Plumber, Electrician, AC Technician, etc.).

---

## Data Contract (Extracted Intent JSON)

```json
{
  "service_type": "AC Gas Leak Repair",
  "service_details": "Gas leak near outdoor unit copper joint",
  "location": "DHA Phase 5 Lahore",
  "time": "Immediately",
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
pip install httpx
```

Set environment variables:

```bash
export LLM_API_KEY="your_api_key"
export LLM_BASE_URL="https://generativelanguage.googleapis.com/v1beta/openai"
export LLM_MODEL="gemini-2.5-flash"
```

### 3) Backend Setup (Node.js)

```bash
cd backend
npm install
npm run dev
```

### 4) Mobile App Setup (Flutter)

```bash
cd mobile_app
flutter pub get
flutter run
```

---

## Repository Structure

```text
karigar.AI/
├── ai_agents/
│   └── intent_extractor.py
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
