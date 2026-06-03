"""
ChatAgent — ARKO in-app AI Coach (conversational)
==================================================
Multi-turn chatbot khusus fitness & nutrisi, sadar konteks data user.
Guardrail (bukan fine-tuning literal): system prompt ketat membatasi topik
hanya seputar fitness/nutrisi/ARKO. Di luar itu → menolak sopan.
"""

import os

# Topik yang diizinkan dijelaskan lewat system prompt (guardrail).
SYSTEM_PROMPT = """You are ARKO Coach, the in-app AI assistant inside the ARKO fitness app.

STRICT SCOPE — you ONLY help with:
- Exercise, workouts, training plans, sets/reps, exercise form & technique
- Nutrition, calories, macros, meal ideas, hydration
- Recovery, rest days, sleep as it relates to training
- Interpreting the user's OWN data shown below (calories, streak, workouts, muscles)
- How to use the ARKO app's features

REFUSE everything else. If asked about coding, politics, general trivia, homework,
news, relationships, or anything unrelated to fitness/nutrition, politely decline
in ONE sentence and steer back, e.g. "I'm your fitness coach — let's keep it to
training and nutrition! What would you like to work on?"

STYLE:
- Concise: 2-4 sentences. No long essays.
- Warm, motivating, practical. Reference the user's real numbers when relevant.
- For anything medical (injury, pain, conditions), add a brief reminder to consult
  a professional. Never diagnose.
- Never invent the user's data; only use what's provided.
"""


def _format_context(ctx: dict) -> str:
    if not ctx:
        return "USER CONTEXT: (no data available yet)"
    lines = ["USER CONTEXT (the user you are talking to):"]
    if ctx.get("name"):            lines.append(f"- Name: {ctx['name']}")
    if ctx.get("fitness_level"):   lines.append(f"- Fitness level: {ctx['fitness_level']}")
    if ctx.get("calorie_goal") is not None:
        lines.append(f"- Daily calorie goal: {ctx['calorie_goal']} kcal")
    if ctx.get("active_energy") is not None:
        lines.append(f"- Calories burned today: {ctx['active_energy']} kcal")
    if ctx.get("steps") is not None:
        lines.append(f"- Steps today: {ctx['steps']}")
    if ctx.get("streak_days") is not None:
        lines.append(f"- Current streak: {ctx['streak_days']} days")
    if ctx.get("recent_workouts"):
        lines.append(f"- Recent workouts: {', '.join(ctx['recent_workouts'][:5])}")
    if ctx.get("muscles_trained_7d"):
        lines.append(f"- Muscles trained (7d): {ctx['muscles_trained_7d']}")
    return "\n".join(lines)


def chat_reply(messages: list, context: dict) -> str:
    """
    messages: [{"role": "user"|"assistant", "content": "..."}] (riwayat chat)
    context : dict data user
    Returns: balasan asisten (string).
    """
    from litellm import completion

    system = SYSTEM_PROMPT + "\n\n" + _format_context(context)
    full_messages = [{"role": "system", "content": system}] + messages[-10:]

    resp = completion(
        model="groq/llama-3.3-70b-versatile",
        api_key=os.getenv("GROQ_API_KEY"),
        messages=full_messages,
        temperature=0.6,
        max_tokens=300,
    )
    return resp.choices[0].message.content.strip()


def local_fallback_reply(messages: list, context: dict) -> str:
    """Balasan rule-based kalau LLM/jaringan tidak tersedia."""
    last = ""
    for m in reversed(messages):
        if m.get("role") == "user":
            last = m.get("content", "").lower()
            break

    goal   = context.get("calorie_goal", 0)
    burned = context.get("active_energy", 0)
    streak = context.get("streak_days", 0)

    if any(w in last for w in ["nutri", "makan", "kalori", "protein", "diet", "eat", "food", "meal"]):
        return (f"For your {goal} kcal goal, aim for ~1.6–2g protein per kg bodyweight, "
                "fill half your plate with veggies, and prioritize whole foods. "
                "Log meals in the Nutrition tab to track macros. (Not medical advice.)")
    if any(w in last for w in ["rest", "recover", "sore", "istirahat", "pegal"]):
        return ("Recovery matters as much as training. Aim for 7–9h sleep, hydrate, and give "
                "each muscle group ~48h before training it again. Check the Rest Day Planner in Tools.")
    if any(w in last for w in ["workout", "latihan", "exercise", "train", "rutin"]):
        return (f"You've burned {burned} kcal today with a {streak}-day streak — nice! "
                "Open the Workouts tab for a template, or let the AI recommend one on Home.")
    return ("I'm your ARKO fitness coach! Ask me about workouts, exercise form, nutrition, "
            "or your progress. (AI is offline right now, so this is a quick tip — "
            "reconnect for personalized answers.)")
