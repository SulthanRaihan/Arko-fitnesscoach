"""
ARKO Backend — FastAPI Server
==============================
REST API endpoints yang dipanggil oleh iOS app.
Crew.py di-import sebagai orchestrator.
"""

import os
from dotenv import load_dotenv

# Load .env untuk local dev; di Cloud Run pakai env vars dari Secret Manager
load_dotenv()

# Kalau GROQ_API_KEY belum ada di env, coba ambil dari Google Secret Manager
if not os.getenv("GROQ_API_KEY"):
    try:
        from google.cloud import secretmanager
        client = secretmanager.SecretManagerServiceClient()
        project_id = os.getenv("GOOGLE_CLOUD_PROJECT", "arko-fitnesscoach")
        name = f"projects/{project_id}/secrets/GROQ_API_KEY/versions/latest"
        response = client.access_secret_version(request={"name": name})
        os.environ["GROQ_API_KEY"] = response.payload.data.decode("UTF-8")
    except Exception:
        pass  # local dev tanpa Google Cloud tetap jalan

from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from crew import (
    run_health_insight_crew,
    run_form_feedback_crew,
    run_progress_insight_crew,
    run_recommendation_narration,
)
from agents.apple_health_agent import mock_a2a_response
from agents.healthy_agent import recommend_workout, generate_program
from agents.ml_agent import generate_form_report
from agents.chat_agent import chat_reply, local_fallback_reply
from agent_card import APPLE_HEALTH_AGENT_CARD, UI_AGENT_CARD, QA_AGENT_CARD

app = FastAPI(
    title="ARKO AI Fitness Coach API",
    version="1.0.0",
    description="CrewAI backend for ARKO iOS app",
)

# Fix emoji/unicode encoding agar tidak rusak di browser
app.router.default_response_class = JSONResponse

import json
from fastapi.responses import Response

class UnicodeJSONResponse(JSONResponse):
    def render(self, content) -> bytes:
        return json.dumps(content, ensure_ascii=False).encode("utf-8")


# ── Request / Response Models ─────────────────────────────────────────────────

class HealthData(BaseModel):
    active_energy: float     # kcal burned today
    calorie_goal: int        # user's daily goal
    steps: int
    resting_hr: int          # bpm
    sleep_hours: float
    streak_days: int


class FormData(BaseModel):
    exercise: str            # e.g. "Squat"
    keypoints: list          # Vision framework joint data
    user_level: str = "beginner"   # beginner | intermediate | advanced


class AgentResponse(BaseModel):
    success: bool
    data: str
    agent_used: str


class RecommendationInput(BaseModel):
    target_calories: float
    active_energy_burned: float
    available_minutes: int = 30
    preferred_intensity: str = "moderate"  # easy | moderate | hard
    recent_exercise_ids: list = []


class FormEvent(BaseModel):
    status: str          # good | not_deep | knee_alignment | not_visible | low_confidence
    timestamp: float     # detik sejak workout dimulai


class FormReportInput(BaseModel):
    exercise: str = "Squat"
    events: list[FormEvent]


class ProgramInput(BaseModel):
    goal: str = "build_muscle"   # build_muscle | lose_weight | strength | endurance
    days_per_week: int = 4
    minutes: int = 45


class WorkoutSummaryInput(BaseModel):
    total_workouts_7d: int = 0
    total_minutes_7d: int = 0
    total_calories_7d: int = 0
    avg_session_minutes: int = 0
    streak_days: int = 0
    last_workout_days_ago: int = 0
    muscles_trained: dict = {}   # e.g. {"chest": 2, "legs": 1, "back": 0}


class ProgressInsightInput(BaseModel):
    health: HealthData
    workout_summary: WorkoutSummaryInput


# ── Endpoints ─────────────────────────────────────────────────────────────────

@app.get("/")
def root():
    return {"status": "ARKO backend running", "agents": ["UIAgent", "HealthKitAgent", "QAAgent"]}


# ── A2A Discovery Endpoints (Agent Cards) ─────────────────────────────────────

@app.get("/.well-known/agent.json")
def agent_card():
    """Main agent card — required by A2A protocol for discovery."""
    return APPLE_HEALTH_AGENT_CARD

@app.get("/agents/apple-health/.well-known/agent.json")
def apple_health_card():
    return APPLE_HEALTH_AGENT_CARD

@app.get("/agents/ui/.well-known/agent.json")
def ui_agent_card():
    return UI_AGENT_CARD

@app.get("/agents/qa/.well-known/agent.json")
def qa_agent_card():
    return QA_AGENT_CARD


@app.post("/health-insights", response_model=AgentResponse)
async def health_insights(data: HealthData):
    """
    iOS → HealthKitAgent → QAAgent → iOS
    Dipanggil setiap kali user buka Home screen.
    """
    try:
        result = run_health_insight_crew(data.model_dump())
        return AgentResponse(
            success=True,
            data=str(result),
            agent_used="HealthKitAgent → QAAgent",
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/analyze-form", response_model=AgentResponse)
async def analyze_form(data: FormData):
    """
    iOS → UIAgent → QAAgent → iOS
    Dipanggil dari FormCheckView ketika Vision mendeteksi pose.
    """
    try:
        result = run_form_feedback_crew(
            exercise=data.exercise,
            keypoints=data.keypoints,
            user_level=data.user_level,
        )
        return AgentResponse(
            success=True,
            data=str(result),
            agent_used="UIAgent → QAAgent",
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/workout-recommendation", response_model=AgentResponse)
async def workout_recommendation(data: HealthData):
    """
    iOS → HealthKitAgent → UIAgent → QAAgent → iOS
    Dipanggil dari WorkoutsView untuk AI recommendations.
    """
    try:
        # HealthKit agent analyze dulu, lalu UI agent format jadi workout list
        health_result = run_health_insight_crew(data.model_dump())
        return AgentResponse(
            success=True,
            data=str(health_result),
            agent_used="HealthKitAgent → UIAgent → QAAgent",
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── Workout Program (HealthyAgent) ────────────────────────────────────────────

@app.post("/generate-program")
async def workout_program(input: ProgramInput):
    """
    HealthyAgent generates a goal-based weekly workout program.
    """
    try:
        program = generate_program(
            goal=input.goal,
            days_per_week=input.days_per_week,
            minutes=input.minutes,
        )
        return UnicodeJSONResponse(content=program)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── Form Report (MLAgent) ─────────────────────────────────────────────────────

@app.post("/form-report")
async def form_report(input: FormReportInput):
    """
    MLAgent aggregates form events from a workout session
    into a structured report (Lesson 10).
    """
    try:
        events_dicts = [{"status": e.status, "timestamp": e.timestamp} for e in input.events]
        report = generate_form_report(events_dicts, exercise=input.exercise)
        return UnicodeJSONResponse(content=report)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── Workout Recommendation (HealthyAgent) ─────────────────────────────────────

@app.post("/recommend-workout")
async def workout_recommendation(input: RecommendationInput):
    """
    HealthyAgent: rule-based scoring (Lesson 9) + Groq LLM narration.
    Returns structured plan enriched with a personalized ai_narration field.
    """
    try:
        plan = recommend_workout(
            target_calories=input.target_calories,
            active_energy_burned=input.active_energy_burned,
            available_minutes=input.available_minutes,
            preferred_intensity=input.preferred_intensity,
            recent_exercise_ids=input.recent_exercise_ids,
        )
        # LLM narrates WHY this plan fits the user today
        health_ctx = {
            "active_energy": input.active_energy_burned,
            "calorie_goal": input.target_calories,
            "steps": 0,
            "streak_days": 0,
        }
        try:
            narration = run_recommendation_narration(plan, health_ctx)
            plan["ai_narration"] = narration
        except Exception:
            plan["ai_narration"] = None   # fallback: show plan without narration
        return UnicodeJSONResponse(content=plan)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/progress-insight")
async def progress_insight(input: ProgressInsightInput):
    """
    ProgressAgent + QAAgent: analyzes 7-day workout history + today's health data.
    Returns personalized progress report with highlights and recovery status.
    """
    try:
        health_dict   = input.health.model_dump()
        summary_dict  = input.workout_summary.model_dump()
        raw_result    = run_progress_insight_crew(health_dict, summary_dict)

        # Parse JSON from LLM output — handle wrapped text gracefully
        import json, re
        result_str = str(raw_result)
        json_match = re.search(r'\{.*\}', result_str, re.DOTALL)
        if json_match:
            parsed = json.loads(json_match.group())
        else:
            parsed = {
                "summary": result_str[:300],
                "highlights": [],
                "next_recommendation": "",
                "recovery_status": "good",
            }

        return UnicodeJSONResponse(content={
            "success": True,
            "summary": parsed.get("summary", ""),
            "highlights": parsed.get("highlights", []),
            "next_recommendation": parsed.get("next_recommendation", ""),
            "recovery_status": parsed.get("recovery_status", "good"),
            "agent_used": "ProgressAgent → QAAgent",
        })
    except Exception:
        # LLM/network unavailable → rule-based local report so the app still works
        return UnicodeJSONResponse(content=_local_progress_report(
            input.health.model_dump(), input.workout_summary.model_dump()))


def _local_progress_report(health: dict, summary: dict) -> dict:
    """Rule-based progress report — runs without any LLM/network."""
    workouts = summary.get("total_workouts_7d", 0)
    minutes  = summary.get("total_minutes_7d", 0)
    streak   = summary.get("streak_days", 0)
    muscles  = summary.get("muscles_trained", {}) or {}
    trained  = [m for m, c in muscles.items() if c > 0]
    skipped  = [m for m, c in muscles.items() if c == 0]
    sleep    = health.get("sleep_hours", 7)

    if workouts == 0:
        summary_text = "No workouts logged this week yet. Today is a great day to start — even a short session builds momentum."
    else:
        summary_text = (f"You completed {workouts} workout(s) this week for {minutes} active minutes, "
                        f"with a {streak}-day streak. Keep the consistency going!")

    highlights = []
    if streak >= 2:
        highlights.append(f"{streak}-day streak — consistency is your superpower.")
    if trained:
        highlights.append(f"Trained: {', '.join(t.capitalize() for t in trained[:3])}.")
    if skipped:
        highlights.append(f"Haven't hit {', '.join(s.capitalize() for s in skipped[:3])} this week.")
    if not highlights:
        highlights = ["Log your first workout to unlock personalized insights."]

    if skipped:
        next_rec = f"Schedule a session targeting {skipped[0].capitalize()} next to balance your training."
    else:
        next_rec = "Add a light recovery or mobility session to aid muscle repair."

    if sleep < 6:
        recovery = "tired"
    elif streak >= 6:
        recovery = "overtraining"
    else:
        recovery = "good"

    return {
        "success": True,
        "summary": summary_text,
        "highlights": highlights[:3],
        "next_recommendation": next_rec,
        "recovery_status": recovery,
        "agent_used": "ProgressAgent (local fallback)",
    }


# ── Chatbot (ARKO Coach) ──────────────────────────────────────────────────────

class ChatMessage(BaseModel):
    role: str       # "user" | "assistant"
    content: str

class ChatInput(BaseModel):
    messages: list[ChatMessage]
    context: dict = {}

@app.post("/chat")
async def chat(input: ChatInput):
    """ARKO Coach — fitness/nutrition chatbot, context-aware, scope-guarded."""
    msgs = [{"role": m.role, "content": m.content} for m in input.messages]
    try:
        reply = chat_reply(msgs, input.context)
    except Exception:
        reply = local_fallback_reply(msgs, input.context)  # Groq blocked → offline tip
    return UnicodeJSONResponse(content={"reply": reply})


# ── A2A Endpoints ─────────────────────────────────────────────────────────────

@app.post("/a2a/apple-health-task")
async def apple_health_a2a(data: HealthData):
    """
    A2A Protocol endpoint — AppleHealthAgent
    Returns calorie data in A2A JSON format (jsonrpc 2.0).
    iOS SwiftUI view parses artifacts[0].parts directly.
    """
    return UnicodeJSONResponse(content=mock_a2a_response(data.model_dump()))


@app.get("/a2a/apple-health-task/mock")
def apple_health_mock():
    """GET endpoint — returns hardcoded mock A2A response for UI testing."""
    return UnicodeJSONResponse(content=mock_a2a_response({
        "active_energy": 342,
        "calorie_goal": 600,
        "steps": 6240,
        "resting_hr": 68,
        "sleep_hours": 7.5,
        "streak_days": 4,
    }))


# ── Run ───────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
