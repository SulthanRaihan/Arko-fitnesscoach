"""
HealthyAgent — Workout Recommendation Engine
=============================================
Berdasarkan Lesson 9: Intelligent Workout Recommendations
- Rule-based scoring algorithm
- Safety guardrails
- External data ready (sekarang pakai mock catalog)
"""

from crewai import Agent, LLM
import os


def create_healthy_agent() -> Agent:
    llm = LLM(
        model="groq/llama-3.3-70b-versatile",
        api_key=os.getenv("GROQ_API_KEY"),
        temperature=0.3,
    )

    return Agent(
        role="Workout Recommendation Engineer",
        goal=(
            "Build personalized workout plans based on the user's daily calorie "
            "target, energy burned so far, available time, preferred intensity, "
            "and recent workout history. Apply safety guardrails."
        ),
        backstory=(
            "You are a certified personal trainer who specializes in evidence-based, "
            "rule-driven workout programming. You use external exercise databases for "
            "breadth but apply local rules for final decisions. You never make extreme "
            "calorie promises, always include warm-up/cooldown when time allows, and "
            "respect the user's energy level."
        ),
        llm=llm,
        verbose=True,
        allow_delegation=False,
    )


# ── Built-in Exercise Catalog ────────────────────────────────────────────────
# Setiap exercise: name, intensity, kcal/min (rough), muscle group, equipment

EXERCISE_CATALOG = [
    # CARDIO
    {"id": "walking",          "name": "Brisk Walking",      "type": "cardio",   "intensity": "easy",     "kcal_per_min": 4,  "muscle": "fullBody", "equipment": "none",       "form_check": False},
    {"id": "jogging",          "name": "Light Jogging",      "type": "cardio",   "intensity": "moderate", "kcal_per_min": 8,  "muscle": "fullBody", "equipment": "none",       "form_check": False},
    {"id": "running",          "name": "Running",            "type": "cardio",   "intensity": "hard",     "kcal_per_min": 12, "muscle": "fullBody", "equipment": "none",       "form_check": False},
    {"id": "cycling",          "name": "Cycling",            "type": "cardio",   "intensity": "moderate", "kcal_per_min": 9,  "muscle": "legs",     "equipment": "bike",       "form_check": False},
    {"id": "hiit",             "name": "HIIT Circuit",       "type": "cardio",   "intensity": "hard",     "kcal_per_min": 14, "muscle": "fullBody", "equipment": "none",       "form_check": False},
    {"id": "jumping_jacks",    "name": "Jumping Jacks",      "type": "cardio",   "intensity": "moderate", "kcal_per_min": 8,  "muscle": "fullBody", "equipment": "none",       "form_check": False},

    # STRENGTH (bodyweight)
    {"id": "pushup",           "name": "Push-ups",           "type": "strength", "intensity": "moderate", "kcal_per_min": 7,  "muscle": "chest",    "equipment": "none",       "form_check": True},
    {"id": "squat",            "name": "Bodyweight Squat",   "type": "strength", "intensity": "moderate", "kcal_per_min": 6,  "muscle": "legs",     "equipment": "none",       "form_check": True},
    {"id": "lunge",            "name": "Walking Lunges",     "type": "strength", "intensity": "moderate", "kcal_per_min": 7,  "muscle": "legs",     "equipment": "none",       "form_check": True},
    {"id": "plank",            "name": "Plank Hold",         "type": "strength", "intensity": "moderate", "kcal_per_min": 5,  "muscle": "core",     "equipment": "none",       "form_check": True},
    {"id": "burpee",           "name": "Burpees",            "type": "strength", "intensity": "hard",     "kcal_per_min": 11, "muscle": "fullBody", "equipment": "none",       "form_check": False},
    {"id": "mountain_climber", "name": "Mountain Climbers",  "type": "strength", "intensity": "hard",     "kcal_per_min": 10, "muscle": "core",     "equipment": "none",       "form_check": False},

    # MOBILITY / RECOVERY
    {"id": "yoga",             "name": "Yoga Flow",          "type": "mobility", "intensity": "easy",     "kcal_per_min": 3,  "muscle": "fullBody", "equipment": "mat",        "form_check": False},
    {"id": "stretch",          "name": "Full Body Stretch",  "type": "flexibility", "intensity": "easy",  "kcal_per_min": 2,  "muscle": "fullBody", "equipment": "none",       "form_check": False},
    {"id": "foam_roll",        "name": "Foam Rolling",       "type": "mobility", "intensity": "easy",     "kcal_per_min": 2,  "muscle": "fullBody", "equipment": "foam_roller","form_check": False},
]


# ── Scoring Algorithm (port dari Lesson 9 PPT) ────────────────────────────────

def score_candidate(
    candidate: dict,
    remaining_calories: float,
    available_minutes: int,
    preferred_intensity: str,
    recent_exercise_ids: list,
) -> float:
    """
    score = calorieFit*0.45 + durationFit*0.20 + intensityFit*0.20
          + noveltyFit*0.10 + equipmentFit*0.05 - safetyPenalty
    """
    # Estimasi kalori untuk durasi available
    estimated_kcal = candidate["kcal_per_min"] * available_minutes

    # 1. calorieFit — semakin dekat ke target, semakin tinggi
    if remaining_calories <= 0:
        # Sudah lewat target → favor recovery/stretching
        calorie_fit = 1.0 if candidate["type"] in ["mobility", "flexibility"] else 0.2
    else:
        ratio = min(estimated_kcal / remaining_calories, 2.0)
        # Best score saat ratio = 1.0 (pas), drop kalau terlalu kurang/lebih
        calorie_fit = max(0, 1 - abs(1 - ratio) * 0.7)

    # 2. durationFit — semua kandidat sama durasi, jadi nilai konstan
    duration_fit = 1.0 if available_minutes >= 10 else 0.6

    # 3. intensityFit
    if candidate["intensity"] == preferred_intensity:
        intensity_fit = 1.0
    elif (candidate["intensity"] == "moderate" and preferred_intensity in ["easy", "hard"]):
        intensity_fit = 0.7  # moderate adjacent ke easy/hard
    else:
        intensity_fit = 0.3

    # 4. noveltyFit — turunkan score kalau baru dilakukan
    novelty_fit = 0.3 if candidate["id"] in recent_exercise_ids else 1.0

    # 5. equipmentFit — favor "none"
    equipment_fit = 1.0 if candidate["equipment"] == "none" else 0.5

    # 6. safetyPenalty — kalau intensity "hard" tapi available time pendek
    safety_penalty = 0
    if candidate["intensity"] == "hard" and available_minutes < 15:
        safety_penalty = 0.3
    if candidate["intensity"] == "hard" and remaining_calories <= 0:
        safety_penalty = 0.5  # jangan kasih hard kalau sudah lewat target

    return (
        calorie_fit * 0.45
        + duration_fit * 0.20
        + intensity_fit * 0.20
        + novelty_fit * 0.10
        + equipment_fit * 0.05
        - safety_penalty
    )


# ── Safety Policy ─────────────────────────────────────────────────────────────

def generate_program(goal: str, days_per_week: int = 4, minutes: int = 45) -> dict:
    """
    Generate weekly workout program berdasarkan goal user.
    goal: build_muscle | lose_weight | strength | endurance
    """
    # Template split per goal
    splits = {
        "build_muscle": {
            "name": "Hypertrophy Split",
            "rep_range": "8-12 reps",
            "days_map": {
                3: ["Push", "Pull", "Legs"],
                4: ["Chest & Triceps", "Back & Biceps", "Legs", "Shoulders & Core"],
                5: ["Chest", "Back", "Legs", "Shoulders", "Arms & Core"],
                6: ["Push", "Pull", "Legs", "Push", "Pull", "Legs"],
            },
        },
        "lose_weight": {
            "name": "Fat Loss Circuit",
            "rep_range": "12-20 reps + cardio",
            "days_map": {
                3: ["Full Body + Cardio", "HIIT", "Full Body + Cardio"],
                4: ["Upper + Cardio", "HIIT", "Lower + Cardio", "Cardio + Core"],
                5: ["Full Body", "HIIT", "Upper", "Cardio", "Lower"],
                6: ["Full Body", "HIIT", "Upper", "Cardio", "Lower", "Active Recovery"],
            },
        },
        "strength": {
            "name": "Strength Program",
            "rep_range": "3-5 reps, heavy",
            "days_map": {
                3: ["Squat Focus", "Bench Focus", "Deadlift Focus"],
                4: ["Squat", "Bench", "Deadlift", "Overhead Press"],
                5: ["Squat", "Bench", "Deadlift", "Press", "Accessory"],
                6: ["Squat", "Bench", "Deadlift", "Squat", "Bench", "Accessory"],
            },
        },
        "endurance": {
            "name": "Endurance Plan",
            "rep_range": "high reps + steady cardio",
            "days_map": {
                3: ["Cardio Long", "Bodyweight Circuit", "Cardio Intervals"],
                4: ["Cardio Long", "Circuit", "Cardio Intervals", "Mobility"],
                5: ["Cardio Long", "Circuit", "Intervals", "Tempo Run", "Mobility"],
                6: ["Cardio Long", "Circuit", "Intervals", "Tempo", "Circuit", "Recovery"],
            },
        },
    }

    config = splits.get(goal, splits["build_muscle"])
    days_per_week = max(3, min(6, days_per_week))
    day_names = config["days_map"].get(days_per_week, config["days_map"][4])

    # Map nama hari ke exercises dari catalog
    days = []
    for i, day_name in enumerate(day_names):
        exercises = _exercises_for_day(day_name, goal, minutes)
        est_kcal = sum(e["estimated_kcal"] for e in exercises)
        days.append({
            "day_number": i + 1,
            "name": day_name,
            "exercises": exercises,
            "estimated_calories": round(est_kcal, 1),
            "estimated_minutes": minutes,
        })

    return {
        "goal": goal,
        "program_name": config["name"],
        "rep_range": config["rep_range"],
        "days_per_week": days_per_week,
        "minutes_per_session": minutes,
        "days": days,
        "source_provider": "ARKO HealthyAgent (program v1)",
        "safety_notes": generate_safety_notes("moderate", minutes),
    }


def _exercises_for_day(day_name: str, goal: str, minutes: int) -> list:
    """Pilih exercises dari catalog yang cocok dengan nama hari."""
    name_lower = day_name.lower()

    # Tentukan muscle/type filter berdasarkan nama hari
    keyword_map = {
        "push": ["chest", "shoulders", "arms"],
        "pull": ["back", "arms"],
        "leg": ["legs"],
        "chest": ["chest"],
        "back": ["back"],
        "shoulder": ["shoulders"],
        "arm": ["arms"],
        "core": ["core"],
        "full body": ["chest", "back", "legs", "core"],
        "upper": ["chest", "back", "shoulders", "arms"],
        "lower": ["legs", "core"],
    }

    target_muscles = []
    for kw, muscles in keyword_map.items():
        if kw in name_lower:
            target_muscles = muscles
            break

    # Cardio/HIIT days
    if any(k in name_lower for k in ["cardio", "hiit", "interval", "circuit", "run", "tempo"]):
        candidates = [c for c in EXERCISE_CATALOG if c["type"] == "cardio"]
    elif any(k in name_lower for k in ["mobility", "recovery", "stretch"]):
        candidates = [c for c in EXERCISE_CATALOG if c["type"] in ["mobility", "flexibility"]]
    elif target_muscles:
        candidates = [c for c in EXERCISE_CATALOG if c["muscle"] in target_muscles]
    else:
        candidates = [c for c in EXERCISE_CATALOG if c["type"] == "strength"]

    if not candidates:
        candidates = [c for c in EXERCISE_CATALOG if c["type"] == "strength"]

    # Ambil 4-5 exercise, durasi dibagi rata
    count = min(5, max(3, minutes // 10))
    selected = candidates[:count]
    per_ex_min = max(5, minutes // max(len(selected), 1))

    return [{
        "id": c["id"],
        "name": c["name"],
        "duration_minutes": per_ex_min,
        "estimated_kcal": c["kcal_per_min"] * per_ex_min,
        "muscle": c["muscle"],
        "intensity": c["intensity"],
        "supports_form_check": c["form_check"],
    } for c in selected]


def generate_safety_notes(plan_intensity: str, duration: int) -> list:
    """Tambah safety notes ke setiap plan."""
    notes = []
    if duration >= 5:
        notes.append("Start with a 3-5 minute warm-up to prepare your body.")
    if plan_intensity == "hard":
        notes.append("Reduce intensity if you feel pain, dizziness, or shortness of breath.")
    if duration >= 30:
        notes.append("Stay hydrated throughout your session.")
    if plan_intensity in ["moderate", "hard"]:
        notes.append("Cool down with light stretching for 3-5 minutes after.")
    notes.append("This is general guidance, not medical advice. Consult a professional if needed.")
    return notes


# ── Recommendation Engine ─────────────────────────────────────────────────────

def recommend_workout(
    target_calories: float,
    active_energy_burned: float,
    available_minutes: int,
    preferred_intensity: str = "moderate",
    recent_exercise_ids: list = None,
) -> dict:
    """
    Main recommendation function.
    Returns WorkoutPlan dict siap dikirim ke iOS.
    """
    recent = recent_exercise_ids or []
    remaining = target_calories - active_energy_burned

    # 1. Filter candidates by remaining calories logic
    if remaining <= 0:
        # Goal sudah tercapai → recovery only
        candidates = [c for c in EXERCISE_CATALOG if c["type"] in ["mobility", "flexibility"]]
    else:
        # Filter by intensity preference + adjacent
        intensity_filter = {
            "easy":     ["easy", "moderate"],
            "moderate": ["easy", "moderate", "hard"],
            "hard":     ["moderate", "hard"],
        }
        allowed = intensity_filter.get(preferred_intensity, ["moderate"])
        candidates = [c for c in EXERCISE_CATALOG if c["intensity"] in allowed]

    if not candidates:
        candidates = EXERCISE_CATALOG  # safety: pakai semua

    # 2. Score & rank
    scored = [
        (c, score_candidate(c, remaining, available_minutes, preferred_intensity, recent))
        for c in candidates
    ]
    scored.sort(key=lambda x: x[1], reverse=True)

    # 3. Top 1 sebagai primary, top 2-3 sebagai exercises tambahan kalau waktu cukup
    top = scored[0][0]
    others = [s[0] for s in scored[1:4] if s[1] > 0.4]  # threshold

    # 4. Build plan
    if remaining <= 0:
        title = f"Recovery & Mobility"
        plan_intensity = "easy"
        primary_duration = min(available_minutes, 20)
    else:
        title = f"Today's {top['name']} Session"
        plan_intensity = top["intensity"]
        primary_duration = available_minutes

    exercises = [{
        "id": top["id"],
        "name": top["name"],
        "duration_minutes": primary_duration,
        "estimated_kcal": top["kcal_per_min"] * primary_duration,
        "muscle": top["muscle"],
        "intensity": top["intensity"],
        "supports_form_check": top["form_check"],
    }]

    # Add 1-2 supplementary exercises kalau waktu > 30 min
    if available_minutes > 30 and remaining > 0:
        for o in others[:2]:
            block_dur = max(5, (available_minutes - primary_duration) // 2)
            exercises.append({
                "id": o["id"],
                "name": o["name"],
                "duration_minutes": block_dur,
                "estimated_kcal": o["kcal_per_min"] * block_dur,
                "muscle": o["muscle"],
                "intensity": o["intensity"],
                "supports_form_check": o["form_check"],
            })

    total_kcal = sum(e["estimated_kcal"] for e in exercises)

    return {
        "title": title,
        "estimated_calories": round(total_kcal, 1),
        "duration_minutes": available_minutes,
        "intensity": plan_intensity,
        "exercises": exercises,
        "source_provider": "ARKO HealthyAgent (rule-based v1)",
        "safety_notes": generate_safety_notes(plan_intensity, available_minutes),
    }
