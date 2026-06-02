import SwiftUI

// MARK: - A2A Protocol Models
// Format: Google Agent-to-Agent (A2A) spec — jsonrpc 2.0

struct A2AResponse: Decodable {
    let jsonrpc: String
    let id: String
    let result: A2AResult
}

struct A2AResult: Decodable {
    let id: String
    let sessionId: String
    let status: A2AStatus
    let artifacts: [A2AArtifact]
}

struct A2AStatus: Decodable {
    let state: String
    let timestamp: String
}

struct A2AArtifact: Decodable {
    let name: String
    let description: String
    let parts: [A2APart]
}

struct A2APart: Decodable {
    let type: String
    let data: A2ACalorieData?
    let text: String?
}

struct A2ACalorieData: Decodable {
    let date: String
    let activeEnergyKcal: Double
    let calorieGoalKcal: Int
    let steps: Int
    let restingHrBpm: Int
    let sleepHours: Double
    let streakDays: Int
    let progressPct: Double

    enum CodingKeys: String, CodingKey {
        case date
        case activeEnergyKcal  = "active_energy_kcal"
        case calorieGoalKcal   = "calorie_goal_kcal"
        case steps
        case restingHrBpm      = "resting_hr_bpm"
        case sleepHours        = "sleep_hours"
        case streakDays        = "streak_days"
        case progressPct       = "progress_pct"
    }
}

// MARK: - A2A Service

final class A2AHealthService {
    static let shared = A2AHealthService()
    private init() {}

    private let baseURL = "http://10.24.54.178:8000"

    /// POST real HealthKit data → AppleHealthAgent returns A2A response
    func fetchRealA2A(activeEnergy: Double, calorieGoal: Int,
                      steps: Int, restingHR: Int,
                      streakDays: Int) async throws -> A2AResponse {
        guard let url = URL(string: baseURL + "/a2a/apple-health-task") else {
            throw URLError(.badURL)
        }
        let body: [String: Any] = [
            "active_energy": activeEnergy,
            "calorie_goal":  calorieGoal,
            "steps":         steps,
            "resting_hr":    restingHR,
            "sleep_hours":   7.5,
            "streak_days":   streakDays
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(A2AResponse.self, from: data)
    }

    /// Fetch mock A2A response (fallback kalau backend mati / simulator)
    func fetchMockA2A() async throws -> A2AResponse {
        guard let url = URL(string: baseURL + "/a2a/apple-health-task/mock") else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(A2AResponse.self, from: data)
    }

    /// Extract CalorieData from the first data part of the first artifact
    func extractCalorieData(from response: A2AResponse) -> A2ACalorieData? {
        response.result.artifacts.first?
            .parts.first(where: { $0.type == "data" })?
            .data
    }

    /// Extract insight text from the first text part of the first artifact
    func extractInsight(from response: A2AResponse) -> String? {
        response.result.artifacts.first?
            .parts.first(where: { $0.type == "text" })?
            .text
    }
}

// MARK: - HomeView

struct HomeView: View {
    @StateObject private var healthKit    = HealthKitManager.shared
    @StateObject private var historyStore = FirestoreWorkoutHistoryStore.shared
    @State private var profile = UserProfile.load()

    // A2A data from AppleHealthAgent
    @State private var a2aCalories: A2ACalorieData? = nil
    @State private var a2aInsight: String = "Loading ARKO insight..."
    @State private var isLoadingA2A = false

    // Workout Recommendation from HealthyAgent
    @State private var workoutPlan: WorkoutPlanResponse? = nil
    @State private var isLoadingPlan = false
    @State private var availableMinutes: Int = 30
    @State private var preferredIntensity: String = "moderate"
    @State private var showPlanDetail = false

    private var progress: Double {
        if let a2a = a2aCalories {
            return min(a2a.progressPct / 100.0, 1.0)
        }
        guard profile.calorieGoal > 0 else { return 0 }
        return min(healthKit.activeEnergy / Double(profile.calorieGoal), 1.0)
    }

    private var displayEnergy: Int {
        a2aCalories.map { Int($0.activeEnergyKcal) } ?? Int(healthKit.activeEnergy)
    }

    private var displayGoal: Int {
        a2aCalories?.calorieGoalKcal ?? profile.calorieGoal
    }

    private var displaySteps: Int {
        a2aCalories?.steps ?? healthKit.steps
    }

    private var displayStreak: Int {
        a2aCalories?.streakDays ?? currentStreak
    }

    private var currentStreak: Int {
        let cal = Calendar.current
        let completed = historyStore.sessions.filter { $0.isCompleted }
        var streak = 0
        var checkDate = Date()
        while completed.contains(where: { cal.isDate($0.startedAt, inSameDayAs: checkDate) }) {
            streak += 1
            checkDate = cal.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }
        return streak
    }

    // Gap = kalori yang belum tercapai
    private var calorieGap: Int {
        max(0, displayGoal - displayEnergy)
    }

    private var healthStatus: String {
        healthKit.isAuthorized ? "Connected" : "Not Connected"
    }

    private var healthStatusColor: Color {
        healthKit.isAuthorized ? Color.arkoGreen : Color.orange
    }

    var body: some View {
        ZStack {
            Color.arkoBg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    topBar
                    dateStrip            // ← horizontal day selector
                    calorieHeroCard      // ← lime calorie ring card
                    healthStatusBar      // ← health connection status
                    aiInsightCard        // ← AI insight
                    recommendationCard   // ← today's workout
                    Spacer(minLength: 110)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .task {
            await healthKit.requestAuthorization()
            await fetchA2AData()
            await fetchWorkoutPlan()
        }
        .sheet(isPresented: $showPlanDetail) {
            if let plan = workoutPlan {
                WorkoutPlanDetailView(plan: plan)
            }
        }
        .refreshable {
            await healthKit.fetchAll()
            await fetchA2AData()
            await fetchWorkoutPlan()
        }
    }

    // MARK: - Fetch Workout Recommendation from HealthyAgent

    private func fetchWorkoutPlan() async {
        await MainActor.run { isLoadingPlan = true }
        do {
            let recent = FirestoreWorkoutHistoryStore.shared.sessions
                .prefix(5)
                .flatMap { $0.exercises.map { $0.exercise.id } }
            let plan = try await ARKOAPIService.shared.fetchWorkoutRecommendation(
                targetCalories: Double(profile.calorieGoal),
                activeEnergyBurned: healthKit.activeEnergy,
                availableMinutes: availableMinutes,
                preferredIntensity: preferredIntensity,
                recentExerciseIds: Array(recent)
            )
            await MainActor.run {
                workoutPlan = plan
                isLoadingPlan = false
            }
        } catch {
            await MainActor.run { isLoadingPlan = false }
        }
    }

    // MARK: - Fetch A2A from AppleHealthAgent

    private func fetchA2AData() async {
        await MainActor.run { isLoadingA2A = true }

        // Tunggu HealthKit selesai baca data dulu
        await healthKit.fetchAll()

        // Strategy: backend real → backend mock → local generator
        do {
            let response = try await A2AHealthService.shared.fetchRealA2A(
                activeEnergy: healthKit.activeEnergy,
                calorieGoal: profile.calorieGoal,
                steps: healthKit.steps,
                restingHR: healthKit.restingHR,
                streakDays: currentStreak
            )
            await applyA2A(response, source: "AppleHealthAgent (live)")
            return
        } catch {}

        do {
            let mock = try await A2AHealthService.shared.fetchMockA2A()
            await applyA2A(mock, source: "AppleHealthAgent (mock)")
            return
        } catch {}

        // Final fallback: local rule-based generator (no backend needed)
        await MainActor.run {
            a2aInsight = generateLocalInsight()
            isLoadingA2A = false
        }
    }

    private func applyA2A(_ response: A2AResponse, source: String) async {
        await MainActor.run {
            a2aCalories = A2AHealthService.shared.extractCalorieData(from: response)
            a2aInsight  = A2AHealthService.shared.extractInsight(from: response)
                         ?? generateLocalInsight()
            isLoadingA2A = false
        }
    }

    /// Rule-based insight generator — selalu jalan tanpa backend.
    private func generateLocalInsight() -> String {
        let energy = displayEnergy
        let goal   = displayGoal
        let steps  = displaySteps
        let pct    = goal > 0 ? Int(Double(energy) / Double(goal) * 100) : 0

        if energy == 0 && steps == 0 {
            return "Let's start moving! A short walk now will kickstart your day and build momentum toward your \(goal) kcal goal."
        }
        if pct >= 100 {
            return "Amazing — you've hit your \(goal) kcal goal with \(energy) kcal burned today! Consider a recovery walk or light stretching to wind down."
        }
        if pct >= 75 {
            return "You're at \(pct)% of your goal with \(energy) kcal burned. Just \(goal - energy) kcal to go — a 15-min jog will close the gap easily."
        }
        if pct >= 50 {
            return "Solid progress! \(energy) kcal down (\(pct)% of goal). With \(steps.formatted()) steps so far, a 25-min cardio session would put you on track."
        }
        if pct >= 25 {
            return "You're warming up — \(energy) kcal burned, \(pct)% toward goal. A 30-min brisk walk or quick HIIT session will boost you significantly."
        }
        return "Time to get moving! You've burned \(energy) kcal so far. Try a 20-min workout to jump-start your day and hit \(goal) kcal."
    }

    // MARK: - Health Status Bar

    private var healthStatusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(healthStatusColor)
                .frame(width: 8, height: 8)
            Text("Apple Health: \(healthStatus)")
                .font(.caption.weight(.medium))
                .foregroundStyle(healthStatusColor)
            Spacer()
            if !healthKit.isAuthorized {
                Button {
                    Task { await healthKit.requestAuthorization() }
                } label: {
                    Text("Connect")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.arkoTeal)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(healthStatusColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Calorie Gap Card

    private var calorieGapCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Burned Today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(displayEnergy) kcal")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.arkoTeal)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 1, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text("Daily Goal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(displayGoal) kcal")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 1, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text("Remaining")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(calorieGap > 0 ? "\(calorieGap) kcal" : "Goal met!")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(calorieGap > 0 ? Color.orange : Color.arkoGreen)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .arkoCard()
    }

    // MARK: - Today's Workout Recommendation (HealthyAgent)

    private var recommendationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(
                            colors: [Color.orange, Color.red.opacity(0.85)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 40, height: 40)
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today's Workout")
                        .font(.subheadline.weight(.bold))
                    Text("Powered by HealthyAgent")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await fetchWorkoutPlan() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.orange)
                        .frame(width: 32, height: 32)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Circle())
                        .rotationEffect(.degrees(isLoadingPlan ? 360 : 0))
                        .animation(isLoadingPlan
                                   ? .linear(duration: 1).repeatForever(autoreverses: false)
                                   : .default, value: isLoadingPlan)
                }
                .disabled(isLoadingPlan)
            }

            // Plan body
            if isLoadingPlan {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Building your plan...").font(.subheadline).foregroundStyle(.secondary)
                }
            } else if let plan = workoutPlan {
                planBody(plan: plan)
            } else {
                Text("Tap refresh to get an AI workout suggestion.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            // Intensity + Time pickers
            controlsRow

            // Start button
            if workoutPlan != nil {
                Button {
                    showPlanDetail = true
                } label: {
                    Text("View Plan & Start")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(LinearGradient(
                            colors: [Color.orange, Color.red.opacity(0.85)],
                            startPoint: .leading, endPoint: .trailing))
                        .clipShape(Capsule())
                }
            }
        }
        .arkoCard()
    }

    private func planBody(plan: WorkoutPlanResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(plan.title)
                .font(.headline)
            HStack(spacing: 14) {
                statTag(icon: "clock.fill", value: "\(plan.duration_minutes) min", color: Color.arkoTeal)
                statTag(icon: "flame.fill", value: "\(Int(plan.estimated_calories)) kcal", color: .orange)
                statTag(icon: "bolt.fill", value: plan.intensity.capitalized, color: Color.arkoGreen)
            }
            Text("\(plan.exercises.count) exercise\(plan.exercises.count > 1 ? "s" : "")")
                .font(.caption).foregroundStyle(.secondary)

            // AI narration from HealthyAgent LLM
            if let narration = plan.ai_narration, !narration.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .padding(.top, 2)
                    Text(narration)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineSpacing(3)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func statTag(icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10))
            Text(value).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.12))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    private var controlsRow: some View {
        HStack(spacing: 8) {
            // Time picker
            Menu {
                ForEach([15, 20, 25, 30, 45, 60], id: \.self) { mins in
                    Button("\(mins) min") {
                        availableMinutes = mins
                        Task { await fetchWorkoutPlan() }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "clock").font(.caption2)
                    Text("\(availableMinutes) min").font(.caption.weight(.medium))
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.arkoTeal.opacity(0.12))
                .foregroundStyle(Color.arkoTeal)
                .clipShape(Capsule())
            }

            // Intensity picker
            Menu {
                ForEach(["easy", "moderate", "hard"], id: \.self) { level in
                    Button(level.capitalized) {
                        preferredIntensity = level
                        Task { await fetchWorkoutPlan() }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bolt").font(.caption2)
                    Text(preferredIntensity.capitalized).font(.caption.weight(.medium))
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.arkoGreen.opacity(0.12))
                .foregroundStyle(Color.arkoGreen)
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.arkoLime)
                    .frame(width: 44, height: 44)
                Text("A").font(.system(size: 18, weight: .bold)).foregroundStyle(.black)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(greetingText).font(.caption).foregroundStyle(Color.arkoTextDim)
                Text("Ready to rock the day?")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
            }
            Spacer()
            Image(systemName: "bell.fill")
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.arkoCard)
                .clipShape(Circle())
        }
    }

    // MARK: - Date Strip

    private var dateStrip: some View {
        HStack(spacing: 0) {
            ForEach(weekDates, id: \.self) { date in
                let isToday = Calendar.current.isDateInToday(date)
                VStack(spacing: 6) {
                    Text(dayNumber(date))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(isToday ? .black : .white)
                    Text(dayLetter(date))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(isToday ? .black.opacity(0.7) : Color.arkoTextDim)
                }
                .frame(width: 42, height: 60)
                .background(isToday ? Color.arkoLime : Color.arkoCard)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Calorie Hero Card (lime)

    private var calorieHeroCard: some View {
        HStack(spacing: 16) {
            // Calorie ring
            ZStack {
                Circle()
                    .stroke(Color.black.opacity(0.12), lineWidth: 12)
                    .frame(width: 100, height: 100)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.black, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 1.0), value: progress)
                VStack(spacing: 0) {
                    Text("\(displayEnergy)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                    Text("kcal")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.black.opacity(0.6))
                }
            }

            // Stats
            VStack(alignment: .leading, spacing: 10) {
                Text("Total Calories")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.black)
                Text("\(Int(progress * 100))% of \(displayGoal) kcal goal")
                    .font(.caption)
                    .foregroundStyle(.black.opacity(0.65))

                HStack(spacing: 12) {
                    heroStat(icon: "shoeprints.fill", value: "\(displaySteps)", label: "steps")
                    heroStat(icon: "flame.fill", value: "\(calorieGap)", label: "left")
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Color.arkoLime)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private func heroStat(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(.black.opacity(0.7))
            Text(value).font(.caption.weight(.bold)).foregroundStyle(.black)
            Text(label).font(.caption2).foregroundStyle(.black.opacity(0.6))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.black.opacity(0.08))
        .clipShape(Capsule())
    }

    // MARK: - Date Helpers

    private var weekDates: [Date] {
        let cal = Calendar.current
        let today = Date()
        let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private func dayNumber(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: date)
    }

    private func dayLetter(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f.string(from: date)
    }

    // MARK: - Streak Card

    private var streakCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ZStack {
                    Circle().fill(Color.orange.opacity(0.12)).frame(width: 32, height: 32)
                    Text("🔥").font(.system(size: 16))
                }
                Spacer()
                Text("Streak").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            }
            Text("\(displayStreak)").font(.system(size: 32, weight: .bold, design: .rounded))
            Text("days in a row").font(.caption2).foregroundStyle(.secondary)
        }
        .arkoCard()
        .frame(maxWidth: .infinity)
    }

    // MARK: - Heart Rate Card

    private var heartRateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ZStack {
                    Circle().fill(Color.red.opacity(0.12)).frame(width: 32, height: 32)
                    Image(systemName: "heart.fill").font(.system(size: 15)).foregroundStyle(.red)
                }
                Spacer()
                HStack(spacing: 3) {
                    Circle().fill(Color.arkoGreen).frame(width: 6, height: 6)
                    Text("Normal").font(.caption2.weight(.medium)).foregroundStyle(Color.arkoGreen)
                }
            }
            Text(healthKit.restingHR > 0 ? "\(healthKit.restingHR)" : "--")
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text("bpm").font(.caption2).foregroundStyle(.secondary)
            HRWaveView().frame(height: 24)
        }
        .arkoCard()
        .frame(maxWidth: .infinity)
    }

    // MARK: - AI Insight Card

    private var aiInsightCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(
                            colors: [Color.arkoTeal, .blue.opacity(0.85)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 40, height: 40)
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("ARKO AI Insight")
                        .font(.subheadline.weight(.bold))
                    Text("Powered by AppleHealthAgent")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await fetchA2AData() }
                } label: {
                    Image(systemName: isLoadingA2A ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.arkoTeal)
                        .frame(width: 32, height: 32)
                        .background(Color.arkoTeal.opacity(0.12))
                        .clipShape(Circle())
                        .rotationEffect(.degrees(isLoadingA2A ? 360 : 0))
                        .animation(isLoadingA2A
                                   ? .linear(duration: 1).repeatForever(autoreverses: false)
                                   : .default, value: isLoadingA2A)
                }
                .disabled(isLoadingA2A)
            }

            // Insight body
            if isLoadingA2A {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Analyzing your activity...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(a2aInsight)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }

            // Footer badges
            HStack(spacing: 6) {
                badge(icon: "checkmark.seal.fill", text: "QA Reviewed", color: Color.arkoGreen)
                badge(icon: "lock.shield.fill", text: "A2A Protocol", color: Color.arkoTeal)
            }
        }
        .arkoCard()
    }

    private func badge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9))
            Text(text).font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.12))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    // MARK: - Helpers

    private var greetingText: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 12 { return "Good morning" }
        if h < 17 { return "Good afternoon" }
        return "Good evening"
    }

    private var progressLabel: String {
        switch progress {
        case 0..<0.3: return "Just getting started"
        case 0.3..<0.6: return "Good progress"
        case 0.6..<0.9: return "Almost there!"
        default: return "Goal reached 🎉"
        }
    }
}

// MARK: - HR Wave

private struct HRWaveView: View {
    private let points: [CGFloat] = [0.5, 0.2, 0.9, 0.3, 0.7, 0.4, 0.6, 0.3, 0.8, 0.5]
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width / CGFloat(points.count - 1)
            let h = geo.size.height
            Path { path in
                for (i, val) in points.enumerated() {
                    let point = CGPoint(x: CGFloat(i) * w, y: h * (1 - val))
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            .stroke(Color.red.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - WorkoutPlanDetailView (sheet from Today's Workout card)
// ════════════════════════════════════════════════════════════════════════════

struct WorkoutPlanDetailView: View {
    let plan: WorkoutPlanResponse
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.arkoBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        headerCard
                        exercisesSection
                        safetySection
                        sourceFooter
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Today's Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.orange, Color.red.opacity(0.85)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 70, height: 70)
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text(plan.title).font(.title3.weight(.bold))
            HStack(spacing: 24) {
                planStat(value: "\(plan.duration_minutes)", unit: "min", color: Color.arkoTeal)
                Divider().frame(height: 30)
                planStat(value: "\(Int(plan.estimated_calories))", unit: "kcal", color: .orange)
                Divider().frame(height: 30)
                planStat(value: plan.intensity.capitalized, unit: "level", color: Color.arkoGreen)
            }
        }
        .frame(maxWidth: .infinity)
        .arkoCard(padding: 20)
    }

    private func planStat(value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Exercises", systemImage: "list.bullet.rectangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.arkoTeal)

            ForEach(plan.exercises) { ex in
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.arkoTeal.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: ex.supports_form_check ? "camera.fill" : "figure.run")
                            .foregroundStyle(Color.arkoTeal)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ex.name).font(.subheadline.weight(.semibold))
                        Text("\(ex.duration_minutes) min · \(Int(ex.estimated_kcal)) kcal · \(ex.muscle.capitalized)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if ex.supports_form_check {
                        Text("Form Check")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
                .padding(12)
                .background(Color.arkoCard)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var safetySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Safety Notes", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.arkoGreen)
            ForEach(Array(plan.safety_notes.enumerated()), id: \.offset) { _, note in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.arkoGreen)
                        .padding(.top, 2)
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding()
        .background(Color.arkoGreen.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var sourceFooter: some View {
        HStack(spacing: 4) {
            Image(systemName: "info.circle").font(.caption2)
            Text(plan.source_provider).font(.caption2)
        }
        .foregroundStyle(.secondary)
    }
}
