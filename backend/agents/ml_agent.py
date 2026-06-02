"""
MLAgent — Vision + Core ML Form Feedback Specialist
=====================================================
Sesuai Lesson 10:
- Design Vision dan Core ML pose flow
- Explain built-in Vision models vs custom Core ML models
- Build rule-based form feedback engine
- Generate post-workout form report dari aggregated session events
"""

from crewai import Agent, LLM
from collections import Counter
import os


def create_ml_agent() -> Agent:
    llm = LLM(
        model="groq/llama-3.3-70b-versatile",
        api_key=os.getenv("GROQ_API_KEY"),
        temperature=0.3,
    )

    return Agent(
        role="Vision & Core ML Form Specialist",
        goal=(
            "Analyze pose keypoint sequences from Apple Vision framework, "
            "apply rule-based form feedback, and generate post-workout reports "
            "that help users improve their exercise technique safely."
        ),
        backstory=(
            "You are a computer vision and biomechanics expert. You designed the "
            "ARKO pose detection pipeline: AVFoundation captures frames, Apple Vision's "
            "VNDetectHumanBodyPoseRequest extracts 17 joint keypoints, then a rule-based "
            "engine analyzes joint angles to evaluate form quality. You explain the "
            "tradeoffs between built-in Vision models versus custom Core ML classifiers, "
            "and you produce actionable, encouraging feedback for users."
        ),
        llm=llm,
        verbose=True,
        allow_delegation=False,
    )


# ── Form Status Codes (matches iOS FormAnalyzer) ──────────────────────────────

FORM_STATUS_LABELS = {
    "good":           "Good form",
    "not_deep":       "Squat not deep enough",
    "knee_alignment": "Knees caving — push them out",
    "not_visible":    "Body not fully visible",
    "low_confidence": "Pose confidence too low",
}


def generate_form_report(events: list, exercise: str = "Squat") -> dict:
    """
    Aggregate form events dari satu workout session.
    Input: events = [{"status": "good", "timestamp": 12.5}, ...]
    Output: structured report dict.
    """
    if not events:
        return {
            "exercise": exercise,
            "total_reps": 0,
            "summary": "No reps detected in this session.",
            "form_quality_pct": 0,
            "issues": [],
            "suggestions": ["Try again with full body in frame and good lighting."],
            "status_breakdown": {},
        }

    # Count occurrences of each status
    status_counts = Counter(e.get("status", "low_confidence") for e in events)
    total = len(events)
    good_count = status_counts.get("good", 0)
    form_quality_pct = round((good_count / total) * 100, 1) if total > 0 else 0

    # Identify dominant issues (selain "good")
    issues = []
    for status, count in status_counts.most_common():
        if status == "good":
            continue
        if count >= max(1, total // 5):  # >= 20% atau min 1
            issues.append({
                "status": status,
                "label": FORM_STATUS_LABELS.get(status, status),
                "count": count,
                "pct": round((count / total) * 100, 1),
            })

    # Generate suggestions berdasarkan dominant issues
    suggestions = []
    if "not_deep" in status_counts and status_counts["not_deep"] >= total // 4:
        suggestions.append("Aim for thighs parallel to the floor on each squat.")
    if "knee_alignment" in status_counts and status_counts["knee_alignment"] >= total // 4:
        suggestions.append("Push knees outward in line with your toes.")
    if "not_visible" in status_counts and status_counts["not_visible"] >= total // 4:
        suggestions.append("Step back so your full body is in frame.")
    if "low_confidence" in status_counts and status_counts["low_confidence"] >= total // 4:
        suggestions.append("Improve lighting or wear contrasting clothing.")
    if form_quality_pct >= 80:
        suggestions.insert(0, "Great work! Your form is consistent and safe.")
    elif form_quality_pct >= 50:
        suggestions.insert(0, "Solid effort. Focus on the issues below to improve next session.")
    else:
        suggestions.insert(0, "Let's focus on form before adding intensity.")

    # Summary text
    if form_quality_pct >= 80:
        summary = f"Excellent session — {good_count} of {total} reps with clean form."
    elif form_quality_pct >= 50:
        summary = f"Decent session — {good_count} of {total} reps clean. Room to improve."
    else:
        summary = f"Form needs work — only {good_count} of {total} reps were clean."

    return {
        "exercise": exercise,
        "total_reps": total,
        "summary": summary,
        "form_quality_pct": form_quality_pct,
        "issues": issues,
        "suggestions": suggestions,
        "status_breakdown": dict(status_counts),
        "agent": "MLAgent",
    }
