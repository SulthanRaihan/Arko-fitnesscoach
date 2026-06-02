"""
ProgressAgent — Workout Progress Analyzer
==========================================
Menganalisis workout history + health data 7 hari terakhir untuk
menghasilkan laporan progres personal: pencapaian, muscle balance,
recovery status, dan rekomendasi fokus berikutnya.
"""

import os
from crewai import Agent, Task, LLM


def _make_llm(temperature: float = 0.4) -> LLM:
    return LLM(
        model="groq/llama-3.3-70b-versatile",
        api_key=os.getenv("GROQ_API_KEY"),
        temperature=temperature,
    )


def create_progress_agent() -> Agent:
    return Agent(
        role="Personal Progress Coach",
        goal=(
            "Analyze the user's workout history and daily health metrics to generate "
            "a personalized, motivating progress report. Highlight achievements, "
            "identify muscle imbalances, assess recovery, and recommend the next focus."
        ),
        backstory=(
            "You are an experienced strength and conditioning coach specializing in "
            "long-term athlete development. You read training patterns like a pro — "
            "you spot overtraining early, celebrate consistency, and always give "
            "your athletes one clear, actionable next step. You are concise, warm, "
            "and evidence-based. You never give vague advice."
        ),
        llm=_make_llm(temperature=0.4),
        verbose=True,
        allow_delegation=False,
    )


def create_qa_agent() -> Agent:
    return Agent(
        role="Safety & Quality Reviewer",
        goal=(
            "Review AI-generated fitness progress reports for safety, accuracy, "
            "and App Store health app compliance before delivery to the user."
        ),
        backstory=(
            "You are a certified medical fitness professional. You ensure all "
            "content is safe, contains appropriate disclaimers, avoids medical "
            "claims, and is suitable for general users."
        ),
        llm=_make_llm(temperature=0.1),
        verbose=True,
        allow_delegation=False,
    )


def make_progress_task(agent: Agent, health: dict, workout_summary: dict) -> Task:
    muscles = workout_summary.get("muscles_trained", {})
    trained_str = ", ".join(
        f"{k}: {v}×" for k, v in muscles.items() if v > 0
    ) or "none this week"
    untrained = [k for k, v in muscles.items() if v == 0]
    last_ago = workout_summary.get("last_workout_days_ago", 0)

    return Task(
        description=(
            "Analyze this user's fitness progress for the last 7 days and generate "
            "a personalized report.\n\n"
            "WORKOUT HISTORY (last 7 days):\n"
            f"  Sessions completed : {workout_summary.get('total_workouts_7d', 0)}\n"
            f"  Total active time  : {workout_summary.get('total_minutes_7d', 0)} min\n"
            f"  Total calories     : {workout_summary.get('total_calories_7d', 0)} kcal\n"
            f"  Avg session length : {workout_summary.get('avg_session_minutes', 0)} min\n"
            f"  Current streak     : {workout_summary.get('streak_days', 0)} days\n"
            f"  Last workout       : {last_ago} day(s) ago\n"
            f"  Muscles trained    : {trained_str}\n"
            f"  Muscles skipped    : {', '.join(untrained) or 'none'}\n\n"
            "TODAY'S HEALTH (Apple HealthKit):\n"
            f"  Active energy      : {health.get('active_energy', 0)} kcal\n"
            f"  Daily calorie goal : {health.get('calorie_goal', 600)} kcal\n"
            f"  Steps today        : {health.get('steps', 0)}\n"
            f"  Resting heart rate : {health.get('resting_hr', 0)} bpm\n"
            f"  Last night sleep   : {health.get('sleep_hours', 0)} hrs\n\n"
            "Instructions:\n"
            "- Write a warm, motivating summary (max 2–3 sentences).\n"
            "- List exactly 2–3 specific highlights (achievements OR things to improve).\n"
            "- Give ONE clear recommendation for what to do next (today or tomorrow).\n"
            "- Assess recovery: 'good' if well-rested & not overtrained, "
            "'tired' if sleep < 6 hrs or 5+ consecutive days, "
            "'overtraining' if 6+ days + high resting HR.\n"
            "- Return ONLY valid JSON, no extra text."
        ),
        expected_output=(
            'Valid JSON object with keys: '
            '"summary" (string), '
            '"highlights" (array of 2–3 strings), '
            '"next_recommendation" (string), '
            '"recovery_status" ("good" | "tired" | "overtraining")'
        ),
        agent=agent,
    )


def make_progress_qa_task(agent: Agent) -> Task:
    return Task(
        description=(
            "Review the fitness progress report generated above.\n"
            "Ensure:\n"
            "- No unverified medical claims.\n"
            "- Recovery assessment is reasonable.\n"
            "- Language is encouraging, not alarmist.\n"
            "- Output is valid JSON matching the required schema.\n"
            "If the report is safe and accurate, return it unchanged in the same JSON format. "
            "If not, fix it. Return ONLY valid JSON."
        ),
        expected_output=(
            'Valid JSON object with keys: '
            '"summary", "highlights", "next_recommendation", "recovery_status"'
        ),
        agent=agent,
    )


def make_recommendation_narration_task(agent: Agent, plan: dict, health: dict) -> Task:
    exercises = plan.get("exercises", [])
    ex_list = ", ".join(e.get("name", "") for e in exercises[:3])
    remaining = health.get("calorie_goal", 600) - health.get("active_energy", 0)

    return Task(
        description=(
            "A rule-based algorithm selected the following workout plan for the user. "
            "Your job is to write a short, personal AI narration that explains WHY "
            "this plan fits the user today, based on their health context.\n\n"
            f"SELECTED PLAN:\n"
            f"  Title      : {plan.get('title', '')}\n"
            f"  Exercises  : {ex_list}\n"
            f"  Duration   : {plan.get('duration_minutes', 0)} min\n"
            f"  Est. kcal  : {plan.get('estimated_calories', 0)} kcal\n"
            f"  Intensity  : {plan.get('intensity', 'moderate')}\n\n"
            f"USER HEALTH CONTEXT:\n"
            f"  Burned today   : {health.get('active_energy', 0)} kcal\n"
            f"  Remaining goal : {max(0, remaining):.0f} kcal\n"
            f"  Steps today    : {health.get('steps', 0)}\n"
            f"  Streak         : {health.get('streak_days', 0)} days\n\n"
            "Write 1–2 sentences that feel personal and motivating. "
            "Reference the user's actual numbers. "
            "Return ONLY the narration string, no JSON."
        ),
        expected_output="A 1–2 sentence personalized narration string.",
        agent=agent,
    )
