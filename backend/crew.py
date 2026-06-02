"""
ARKO Fitness Coach — CrewAI Orchestrator
=========================================
Referensi pattern: https://medium.com/@kevin0108dsa/create-an-ai-workforce-with-crewai-292d3fbfacb1

3 Agent yang bekerja sama:
  - UIAgent        : analisis form exercise dari pose keypoints
  - HealthKitAgent : analisis data Apple Health harian
  - QAAgent        : review keamanan & kualitas sebelum ke user
"""

import os
from dotenv import load_dotenv
from crewai import Agent, Task, Crew, Process, LLM
from agents.progress_agent import (
    create_progress_agent,
    create_qa_agent as create_progress_qa_agent,
    make_progress_task,
    make_progress_qa_task,
    make_recommendation_narration_task,
)

load_dotenv()

# ── LLM (Groq — free tier) ────────────────────────────────────────────────────
#   Groq pakai Llama 3.3 70B — cepat, gratis, cocok untuk development.
#   Ganti model ke "anthropic/claude-sonnet-4-6" + ANTHROPIC_API_KEY jika mau Claude.

def make_llm(temperature: float = 0.3) -> LLM:
    return LLM(
        model="groq/llama-3.3-70b-versatile",
        api_key=os.getenv("GROQ_API_KEY"),
        temperature=temperature,
    )


# ── Agents ────────────────────────────────────────────────────────────────────
#   Setiap agent punya: role, goal, backstory (pattern dari artikel laoshi)

ui_agent = Agent(
    role="Fitness UI Coach",
    goal=(
        "Translate raw pose keypoint data from Apple Vision into clear, "
        "human-readable form feedback that helps users fix their exercise technique."
    ),
    backstory=(
        "You are an expert personal trainer with 10 years of experience coaching "
        "athletes of all levels. You can read body mechanics from joint angle data "
        "and keypoints, and you give corrections in a motivating, encouraging tone "
        "tailored to the user's fitness level."
    ),
    llm=make_llm(temperature=0.3),
    verbose=True,
)

healthkit_agent = Agent(
    role="Health Data Analyst",
    goal=(
        "Analyze Apple Health metrics sent from the iOS app and generate "
        "personalized daily insights and workout recommendations based on "
        "the user's current physiological state."
    ),
    backstory=(
        "You are a sports scientist specializing in energy expenditure, recovery, "
        "and performance optimization. You interpret HealthKit data — active energy, "
        "resting heart rate, steps, sleep — detect overtraining signals, and give "
        "evidence-based, practical workout recommendations."
    ),
    llm=make_llm(temperature=0.2),
    verbose=True,
)

qa_agent = Agent(
    role="Safety & Quality Reviewer",
    goal=(
        "Review all AI-generated fitness content before it reaches the user. "
        "Ensure every recommendation is safe, within healthy physiological ranges, "
        "and compliant with App Store health app guidelines."
    ),
    backstory=(
        "You are a certified medical fitness professional and App Store compliance "
        "reviewer. You verify calorie goals are in safe ranges (1200–4000 kcal), "
        "workout intensity matches the user's condition, and all content includes "
        "appropriate safety disclaimers. You are the last line of defense."
    ),
    llm=make_llm(temperature=0.1),
    verbose=True,
)


# ── Tasks ─────────────────────────────────────────────────────────────────────
#   Task dibuat fresh setiap request agar data selalu up-to-date.

def make_health_insight_task(health_data: dict) -> Task:
    return Task(
        description=(
            f"Analyze the following Apple Health data sent from the user's iPhone:\n\n"
            f"  Active Energy : {health_data.get('active_energy', 0)} kcal\n"
            f"  Calorie Goal  : {health_data.get('calorie_goal', 600)} kcal\n"
            f"  Steps         : {health_data.get('steps', 0)}\n"
            f"  Resting HR    : {health_data.get('resting_hr', 0)} bpm\n"
            f"  Sleep         : {health_data.get('sleep_hours', 0)} hrs\n"
            f"  Streak        : {health_data.get('streak_days', 0)} days\n\n"
            "Generate a short daily progress insight (2–3 sentences) and one "
            "concrete workout recommendation that fits today's energy level. "
            "Flag overtraining risk if present."
        ),
        expected_output=(
            "A JSON with: 'insight' (string), 'recommendation' (string), "
            "'overtraining_risk' (boolean), 'progress_pct' (float 0–100)."
        ),
        agent=healthkit_agent,
    )


def make_form_feedback_task(exercise: str, keypoints: list, user_level: str) -> Task:
    return Task(
        description=(
            f"The user is performing '{exercise}'. Fitness level: '{user_level}'.\n\n"
            f"Pose keypoints from Apple Vision: {keypoints}\n\n"
            "Analyze body mechanics and give actionable form corrections. "
            "Focus on the 1–2 most important issues only. "
            "Use language appropriate for their level."
        ),
        expected_output=(
            "A JSON with: 'feedback' (string), "
            "'severity' ('good' | 'warn' | 'error'), 'tip' (string)."
        ),
        agent=ui_agent,
    )


def make_qa_task(content: str) -> Task:
    return Task(
        description=(
            f"Review this AI-generated fitness content for safety and compliance:\n\n"
            f"{content}\n\n"
            "Verify: calorie values are 1200–4000 kcal, intensity is appropriate, "
            "no unverified medical claims, safe for general users. "
            "Approve or modify. Add disclaimer if needed."
        ),
        expected_output=(
            "A JSON with: 'approved' (boolean), "
            "'final_content' (string), 'disclaimer' (string or null)."
        ),
        agent=qa_agent,
    )


# ── Crew Pipelines ────────────────────────────────────────────────────────────
#   Pattern: buat Task → buat Crew → kickoff()

def run_health_insight_crew(health_data: dict) -> str:
    """Pipeline: HealthKitAgent → QAAgent"""
    health_task = make_health_insight_task(health_data)
    qa_task     = make_qa_task("Review the health insight output above.")

    crew = Crew(
        agents=[healthkit_agent, qa_agent],
        tasks=[health_task, qa_task],
        process=Process.sequential,
        verbose=True,
    )
    return crew.kickoff()


def run_form_feedback_crew(exercise: str, keypoints: list, user_level: str = "beginner") -> str:
    """Pipeline: UIAgent → QAAgent"""
    form_task = make_form_feedback_task(exercise, keypoints, user_level)
    qa_task   = make_qa_task("Review the form feedback output above.")

    crew = Crew(
        agents=[ui_agent, qa_agent],
        tasks=[form_task, qa_task],
        process=Process.sequential,
        verbose=True,
    )
    return crew.kickoff()


# ── Progress Insight Pipeline ─────────────────────────────────────────────────

def run_progress_insight_crew(health: dict, workout_summary: dict) -> str:
    """Pipeline: ProgressAgent → QAAgent → personalized progress report."""
    progress_agent = create_progress_agent()
    qa             = create_progress_qa_agent()

    progress_task = make_progress_task(progress_agent, health, workout_summary)
    qa_task       = make_progress_qa_task(qa)

    crew = Crew(
        agents=[progress_agent, qa],
        tasks=[progress_task, qa_task],
        process=Process.sequential,
        verbose=True,
    )
    return str(crew.kickoff())


def run_recommendation_narration(plan: dict, health: dict) -> str:
    """Single-agent task: HealthyAgent narrates why the rule-based plan fits today."""
    narration_task = make_recommendation_narration_task(healthkit_agent, plan, health)

    crew = Crew(
        agents=[healthkit_agent],
        tasks=[narration_task],
        process=Process.sequential,
        verbose=True,
    )
    return str(crew.kickoff()).strip()


# ── Test Lokal ────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print("=" * 60)
    print("  ARKO CrewAI — Test Run")
    print("=" * 60)

    print("\n[1] HealthKitAgent + QAAgent — Daily Insight\n")
    result1 = run_health_insight_crew({
        "active_energy": 342,
        "calorie_goal": 600,
        "steps": 6240,
        "resting_hr": 68,
        "sleep_hours": 7.5,
        "streak_days": 4,
    })
    print("\nResult:", result1)

    print("\n[2] UIAgent + QAAgent — Squat Form Feedback\n")
    result2 = run_form_feedback_crew(
        exercise="Squat",
        keypoints=[
            {"joint": "left_knee",  "angle": 75},
            {"joint": "right_knee", "angle": 73},
            {"joint": "hip",        "angle": 90},
            {"joint": "spine",      "angle": 5},
        ],
        user_level="intermediate",
    )
    print("\nResult:", result2)
