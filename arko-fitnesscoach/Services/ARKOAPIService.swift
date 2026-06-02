import Foundation

// Switch antara production (Railway) dan local dev:
// production → ganti ke URL Railway setelah deploy
// local       → IP Mac di WiFi yang sama, port 8000
private let baseURL: String = {
    #if DEBUG
    return "http://10.24.54.178:8000"   // ganti IP kalau perlu
    #else
    return "https://arko-backend.up.railway.app"  // ganti setelah deploy Railway
    #endif
}()

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Request / Response Models
// ════════════════════════════════════════════════════════════════════════════

struct HealthInsightRequest: Encodable {
    let active_energy: Double
    let calorie_goal: Int
    let steps: Int
    let resting_hr: Int
    let sleep_hours: Double
    let streak_days: Int
}

struct FormAnalysisRequest: Encodable {
    let exercise: String
    let keypoints: [[String: Double]]
    let user_level: String
}

struct AgentResponse: Decodable {
    let success: Bool
    let data: String
    let agent_used: String
}

// MARK: - Workout Recommendation (HealthyAgent)

struct RecommendationRequest: Encodable {
    let target_calories: Double
    let active_energy_burned: Double
    let available_minutes: Int
    let preferred_intensity: String   // easy | moderate | hard
    let recent_exercise_ids: [String]
}

struct RecommendedExercise: Decodable, Identifiable {
    var id: String
    let name: String
    let duration_minutes: Int
    let estimated_kcal: Double
    let muscle: String
    let intensity: String
    let supports_form_check: Bool
}

struct WorkoutPlanResponse: Decodable {
    let title: String
    let estimated_calories: Double
    let duration_minutes: Int
    let intensity: String
    let exercises: [RecommendedExercise]
    let source_provider: String
    let safety_notes: [String]
    let ai_narration: String?   // LLM-generated personalized narration
}

// MARK: - Progress Insight (ProgressAgent)

struct WorkoutSummaryPayload: Encodable {
    let total_workouts_7d: Int
    let total_minutes_7d: Int
    let total_calories_7d: Int
    let avg_session_minutes: Int
    let streak_days: Int
    let last_workout_days_ago: Int
    let muscles_trained: [String: Int]   // muscle → session count this week
}

struct ProgressInsightRequest: Encodable {
    let health: HealthInsightRequest
    let workout_summary: WorkoutSummaryPayload
}

struct ProgressInsightResponse: Decodable {
    let success: Bool
    let summary: String
    let highlights: [String]
    let next_recommendation: String
    let recovery_status: String   // good | tired | overtraining
    let agent_used: String
}

// MARK: - Form Report (MLAgent)

struct FormEventDTO: Encodable {
    let status: String
    let timestamp: Double
}

struct FormReportRequest: Encodable {
    let exercise: String
    let events: [FormEventDTO]
}

struct FormReportIssue: Decodable, Identifiable {
    var id: String { status }
    let status: String
    let label: String
    let count: Int
    let pct: Double
}

struct FormReportResponse: Decodable {
    let exercise: String
    let total_reps: Int
    let summary: String
    let form_quality_pct: Double
    let issues: [FormReportIssue]
    let suggestions: [String]
}

// MARK: - Workout Program (HealthyAgent)

struct ProgramRequest: Encodable {
    let goal: String
    let days_per_week: Int
    let minutes: Int
}

struct ProgramDay: Decodable, Identifiable {
    var id: Int { day_number }
    let day_number: Int
    let name: String
    let exercises: [RecommendedExercise]
    let estimated_calories: Double
    let estimated_minutes: Int
}

struct WorkoutProgramResponse: Decodable {
    let goal: String
    let program_name: String
    let rep_range: String
    let days_per_week: Int
    let minutes_per_session: Int
    let days: [ProgramDay]
    let source_provider: String
    let safety_notes: [String]
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Service
// ════════════════════════════════════════════════════════════════════════════

final class ARKOAPIService {
    static let shared = ARKOAPIService()
    private init() {}

    // MARK: Health Insight

    func fetchHealthInsight(activeEnergy: Double, calorieGoal: Int, steps: Int,
                            restingHR: Int, sleepHours: Double = 7.5, streakDays: Int) async throws -> String {
        let body = HealthInsightRequest(active_energy: activeEnergy, calorie_goal: calorieGoal,
                                        steps: steps, resting_hr: restingHR,
                                        sleep_hours: sleepHours, streak_days: streakDays)
        let response: AgentResponse = try await post(path: "/health-insights", body: body)
        return response.data
    }

    // MARK: Form Feedback (UIAgent)

    func analyzeForm(
        exercise: String,
        keypoints: [[String: Double]],
        userLevel: String = "beginner"
    ) async throws -> String {
        let body = FormAnalysisRequest(
            exercise: exercise,
            keypoints: keypoints,
            user_level: userLevel
        )
        let response: AgentResponse = try await post(path: "/analyze-form", body: body)
        return response.data
    }

    // MARK: Workout Program (HealthyAgent)

    func generateProgram(
        goal: String,
        daysPerWeek: Int = 4,
        minutes: Int = 45
    ) async throws -> WorkoutProgramResponse {
        let body = ProgramRequest(goal: goal, days_per_week: daysPerWeek, minutes: minutes)
        return try await post(path: "/generate-program", body: body)
    }

    // MARK: Form Report (MLAgent)

    func fetchFormReport(
        exercise: String,
        events: [(status: String, timestamp: Double)]
    ) async throws -> FormReportResponse {
        let body = FormReportRequest(
            exercise: exercise,
            events: events.map { FormEventDTO(status: $0.status, timestamp: $0.timestamp) }
        )
        return try await post(path: "/form-report", body: body)
    }

    // MARK: Workout Recommendation

    func fetchWorkoutRecommendation(
        targetCalories: Double,
        activeEnergyBurned: Double,
        availableMinutes: Int = 30,
        preferredIntensity: String = "moderate",
        recentExerciseIds: [String] = []
    ) async throws -> WorkoutPlanResponse {
        let body = RecommendationRequest(
            target_calories: targetCalories,
            active_energy_burned: activeEnergyBurned,
            available_minutes: availableMinutes,
            preferred_intensity: preferredIntensity,
            recent_exercise_ids: recentExerciseIds
        )
        return try await post(path: "/recommend-workout", body: body)
    }

    // MARK: Progress Insight

    func fetchProgressInsight(
        activeEnergy: Double,
        calorieGoal: Int,
        steps: Int,
        restingHR: Int,
        sleepHours: Double,
        streakDays: Int,
        sessions: [WorkoutSession]
    ) async throws -> ProgressInsightResponse {
        let cal = Calendar.current
        let weekAgo = cal.date(byAdding: .day, value: -7, to: Date())!
        let weekSessions = sessions.filter { $0.startedAt >= weekAgo && $0.isCompleted }

        // Compute workout summary on client to keep payload small
        let totalMinutes = weekSessions.reduce(0) { $0 + $1.durationMinutes }
        let totalCalories = Int(weekSessions.reduce(0) { $0 + ($1.caloriesBurned ?? 0) })
        let avgMinutes = weekSessions.isEmpty ? 0 : totalMinutes / weekSessions.count

        // Muscle frequency
        var musclesMap: [String: Int] = [:]
        for group in MuscleGroup.allCases { musclesMap[group.rawValue] = 0 }
        for session in weekSessions {
            for block in session.exercises where block.completedSetsCount > 0 {
                musclesMap[block.exercise.primaryMuscle.rawValue, default: 0] += 1
            }
        }

        // Days since last workout
        let lastWorkout = sessions.first(where: { $0.isCompleted })?.startedAt
        let daysSinceLast = lastWorkout.map {
            cal.dateComponents([.day], from: $0, to: Date()).day ?? 0
        } ?? 0

        let summary = WorkoutSummaryPayload(
            total_workouts_7d: weekSessions.count,
            total_minutes_7d: totalMinutes,
            total_calories_7d: totalCalories,
            avg_session_minutes: avgMinutes,
            streak_days: streakDays,
            last_workout_days_ago: daysSinceLast,
            muscles_trained: musclesMap
        )
        let health = HealthInsightRequest(
            active_energy: activeEnergy,
            calorie_goal: calorieGoal,
            steps: steps,
            resting_hr: restingHR,
            sleep_hours: sleepHours,
            streak_days: streakDays
        )
        let body = ProgressInsightRequest(health: health, workout_summary: summary)
        return try await post(path: "/progress-insight", body: body)
    }

    // MARK: Generic POST

    private func post<B: Encodable, R: Decodable>(path: String, body: B) async throws -> R {
        guard let url = URL(string: baseURL + path) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        req.timeoutInterval = 30
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(R.self, from: data)
    }
}
