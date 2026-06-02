"""
AppleHealthAgent — A2A Protocol Agent
======================================
Agent persona yang membaca Apple HealthKit data dan
mengembalikan response dalam format A2A (Agent-to-Agent) JSON.

Referensi A2A spec: https://google.github.io/A2A
"""

from crewai import Agent, LLM
from datetime import datetime, timezone
import os


def create_apple_health_agent() -> Agent:
    llm = LLM(
        model="groq/llama-3.3-70b-versatile",
        api_key=os.getenv("GROQ_API_KEY"),
        temperature=0.2,
    )

    return Agent(
        role="Apple Health Data Agent",
        goal=(
            "Read Apple HealthKit metrics and return structured health data "
            "in A2A (Agent-to-Agent) protocol JSON format so other agents "
            "and iOS clients can consume it reliably."
        ),
        backstory=(
            "You are a specialized health data bridge agent that interfaces "
            "with Apple HealthKit. You collect daily metrics — active energy, "
            "steps, heart rate, and sleep — then package them into standardized "
            "A2A protocol responses. Other AI agents (HealthKitAgent, UIAgent) "
            "and the iOS SwiftUI frontend consume your output."
        ),
        llm=llm,
        verbose=False,
        allow_delegation=False,
    )


# ── Mock A2A Response ─────────────────────────────────────────────────────────
# This is the exact JSON the SwiftUI view will parse.
# Format follows Google A2A spec: jsonrpc 2.0 + result.artifacts

def mock_a2a_response(health_data: dict) -> dict:
    """
    Generate a mock A2A JSON response with Apple Health calorie data.
    Returns the exact structure that SwiftUI parses.
    """
    active  = health_data.get("active_energy", 342)
    goal    = health_data.get("calorie_goal", 600)
    steps   = health_data.get("steps", 6240)
    hr      = health_data.get("resting_hr", 68)
    sleep   = health_data.get("sleep_hours", 7.5)
    streak  = health_data.get("streak_days", 4)
    progress = round((active / goal) * 100, 1) if goal > 0 else 0

    insight = (
        f"You've burned {active} kcal today ({progress}% of your {goal} kcal goal). "
        f"With {steps:,} steps and a resting HR of {hr} bpm, "
        f"your body is ready for a moderate workout. "
        f"Keep your {streak}-day streak alive!"
    )

    return {
        "jsonrpc": "2.0",
        "id": "apple-health-task-001",
        "result": {
            "id": "task-apple-health-001",
            "sessionId": "session-arko-ios",
            "status": {
                "state": "completed",
                "timestamp": datetime.now(timezone.utc).isoformat()
            },
            "artifacts": [
                {
                    "name": "calorie_report",
                    "description": "Daily calorie and activity data from Apple Health",
                    "parts": [
                        {
                            "type": "data",
                            "data": {
                                "date": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
                                "active_energy_kcal": active,
                                "calorie_goal_kcal": goal,
                                "steps": steps,
                                "resting_hr_bpm": hr,
                                "sleep_hours": sleep,
                                "streak_days": streak,
                                "progress_pct": progress
                            }
                        },
                        {
                            "type": "text",
                            "text": insight
                        }
                    ]
                }
            ]
        }
    }
