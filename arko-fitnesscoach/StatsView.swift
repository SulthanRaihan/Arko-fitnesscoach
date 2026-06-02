import SwiftUI
import Charts

// ════════════════════════════════════════════════════════════════════════════
// MARK: - StatsView (Analytics + Muscle Map + Progress)
// ════════════════════════════════════════════════════════════════════════════

struct StatsView: View {
    @StateObject private var historyStore = FirestoreWorkoutHistoryStore.shared
    @StateObject private var muscleLog    = MuscleLogService.shared
    @StateObject private var healthKit    = HealthKitManager.shared

    @State private var progressInsight: ProgressInsightResponse?
    @State private var insightLoading = false
    @State private var insightError: String?

    var body: some View {
        ZStack {
            Color.arkoBg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header
                    weeklySummaryCard
                    aiProgressCard
                    weeklyChartCard
                    monthlyChartCard
                    bodyMapCard
                    muscleGroupsCard
                    Spacer(minLength: 110)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .task {
            _ = await historyStore.loadAllSessions()
            await muscleLog.fetchLog()
            await fetchProgressInsight()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your Progress").font(.caption).foregroundStyle(Color.arkoTextDim)
                Text("Statistics").font(.title2.weight(.bold)).foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    // MARK: Weekly Summary

    private var weeklySummaryCard: some View {
        HStack(spacing: 16) {
            summaryStat(value: "\(weekSessions.count)", label: "Workouts", icon: "figure.run")
            Divider().frame(height: 36).overlay(Color.white.opacity(0.1))
            summaryStat(value: "\(weekMinutes)", label: "Minutes", icon: "clock.fill")
            Divider().frame(height: 36).overlay(Color.white.opacity(0.1))
            summaryStat(value: "\(weekCalories)", label: "kcal", icon: "flame.fill")
        }
        .arkoCard()
    }

    private func summaryStat(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.caption).foregroundStyle(Color.arkoLime)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label).font(.caption2).foregroundStyle(Color.arkoTextDim)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Weekly Chart (Swift Charts)

    private var weeklyChartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Calories This Week", systemImage: "chart.bar.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.arkoLime)

            Chart(weeklyData, id: \.day) { item in
                BarMark(
                    x: .value("Day", item.day),
                    y: .value("Calories", item.calories)
                )
                .foregroundStyle(Color.arkoLime.gradient)
                .cornerRadius(6)
            }
            .frame(height: 160)
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                    AxisValueLabel().foregroundStyle(Color.arkoTextDim)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().foregroundStyle(Color.arkoTextDim)
                }
            }
        }
        .arkoCard()
    }

    // MARK: Monthly Chart (30 days)

    private var monthlyChartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Activity — Last 30 Days", systemImage: "chart.line.uptrend.xyaxis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.arkoLime)

            Chart(monthlyData, id: \.day) { item in
                if item.calories > 0 {
                    BarMark(
                        x: .value("Day", item.day),
                        y: .value("Calories", item.calories)
                    )
                    .foregroundStyle(
                        item.isCurrentWeek
                        ? Color.arkoLime.gradient
                        : Color.arkoLime.opacity(0.35).gradient
                    )
                    .cornerRadius(3)
                }
            }
            .frame(height: 120)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel().foregroundStyle(Color.arkoTextDim)
                }
            }

            // Legend
            HStack(spacing: 16) {
                legendDot(Color.arkoLime, "This week")
                legendDot(Color.arkoLime.opacity(0.35), "Earlier")
                Spacer()
                Text("\(monthSessions.count) sessions total")
                    .font(.caption2)
                    .foregroundStyle(Color.arkoTextDim)
            }
        }
        .arkoCard()
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label).font(.caption2).foregroundStyle(Color.arkoTextDim)
        }
    }

    // MARK: Body Map (Anatomy Heatmap)

    private var bodyMapCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Muscle Heat Map", systemImage: "figure.arms.open")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.arkoLime)

            if muscleLog.muscleLastTrained.isEmpty {
                Text("Complete a workout to see which muscles you've trained.")
                    .font(.caption)
                    .foregroundStyle(Color.arkoTextDim)
                    .padding(.vertical, 8)
            } else {
                BodyMapView(muscleLastTrained: muscleLog.muscleLastTrained)
                    .frame(maxWidth: .infinity)
            }
        }
        .arkoCard()
    }

    // MARK: Muscle Groups (bar chart)

    private var muscleGroupsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Sets per Muscle (this week)", systemImage: "chart.bar.xaxis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.arkoLime)

            if muscleCounts.isEmpty {
                Text("No workout data yet.")
                    .font(.caption)
                    .foregroundStyle(Color.arkoTextDim)
                    .padding(.vertical, 8)
            } else {
                ForEach(muscleCounts, id: \.muscle) { item in
                    HStack(spacing: 12) {
                        Text(item.muscle.capitalized)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .frame(width: 90, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.08))
                                Capsule()
                                    .fill(Color.arkoLime)
                                    .frame(width: geo.size.width * barRatio(item.count))
                            }
                        }
                        .frame(height: 10)
                        Text("\(item.count)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.arkoLime)
                            .frame(width: 24)
                    }
                }
            }
        }
        .arkoCard()
    }

    // MARK: AI Progress Insight Card

    private var aiProgressCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("AI Progress Report", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.arkoLime)
                Spacer()
                if insightLoading {
                    ProgressView().tint(Color.arkoLime).scaleEffect(0.8)
                } else {
                    Button {
                        Task { await fetchProgressInsight() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundStyle(Color.arkoTextDim)
                    }
                }
            }

            if insightLoading && progressInsight == nil {
                HStack(spacing: 10) {
                    ProgressView().tint(Color.arkoLime)
                    Text("Analyzing your progress...")
                        .font(.caption)
                        .foregroundStyle(Color.arkoTextDim)
                }
                .padding(.vertical, 8)
            } else if let insight = progressInsight {
                // Recovery badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(recoveryColor(insight.recovery_status))
                        .frame(width: 8, height: 8)
                    Text(recoveryLabel(insight.recovery_status))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(recoveryColor(insight.recovery_status))
                    Spacer()
                    Text("via \(insight.agent_used)")
                        .font(.caption2)
                        .foregroundStyle(Color.arkoTextDim)
                }

                // Summary
                Text(insight.summary)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineSpacing(3)

                // Highlights
                if !insight.highlights.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(insight.highlights, id: \.self) { h in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.arkoLime)
                                    .padding(.top, 2)
                                Text(h)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }
                    }
                }

                // Next recommendation
                if !insight.next_recommendation.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.orange)
                        Text(insight.next_recommendation)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange.opacity(0.9))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            } else if let err = insightError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(Color.arkoTextDim)
                    .padding(.vertical, 4)
            } else {
                Text("Complete a workout to get your first AI progress report.")
                    .font(.caption)
                    .foregroundStyle(Color.arkoTextDim)
                    .padding(.vertical, 4)
            }
        }
        .arkoCard()
    }

    private func recoveryColor(_ status: String) -> Color {
        switch status {
        case "tired":        return .orange
        case "overtraining": return .red
        default:             return Color.arkoLime
        }
    }

    private func recoveryLabel(_ status: String) -> String {
        switch status {
        case "tired":        return "Tired — consider lighter session"
        case "overtraining": return "Overtraining risk — rest recommended"
        default:             return "Recovery: Good"
        }
    }

    // MARK: Fetch progress insight

    private func fetchProgressInsight() async {
        guard !historyStore.sessions.isEmpty else { return }
        insightLoading = true
        insightError = nil
        do {
            let result = try await ARKOAPIService.shared.fetchProgressInsight(
                activeEnergy: healthKit.activeEnergy,
                calorieGoal: UserProfile.load().calorieGoal,
                steps: healthKit.steps,
                restingHR: healthKit.restingHR,
                sleepHours: 7.0,
                streakDays: currentStreak,
                sessions: historyStore.sessions
            )
            progressInsight = result
        } catch {
            insightError = "Backend offline — run the Python server to get AI insights."
        }
        insightLoading = false
    }

    private var currentStreak: Int {
        let cal = Calendar.current
        let completed = historyStore.sessions.filter { $0.isCompleted }
        var streak = 0
        var checkDate = Date()
        while true {
            if completed.contains(where: { cal.isDate($0.startedAt, inSameDayAs: checkDate) }) {
                streak += 1
                checkDate = cal.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
            } else { break }
        }
        return streak
    }

    // MARK: Data helpers

    private var weekSessions: [WorkoutSession] {
        let cal = Calendar.current
        let weekAgo = cal.date(byAdding: .day, value: -7, to: Date())!
        return historyStore.sessions.filter { $0.startedAt >= weekAgo }
    }

    private var weekMinutes: Int {
        weekSessions.reduce(0) { $0 + $1.durationMinutes }
    }

    private var weekCalories: Int {
        Int(weekSessions.reduce(0) { $0 + ($1.caloriesBurned ?? 0) })
    }

    private struct DayData { let day: String; let calories: Int }

    private var weeklyData: [DayData] {
        let cal = Calendar.current
        let fmt = DateFormatter(); fmt.dateFormat = "EEE"
        var buckets: [String: Int] = [:]
        var order: [String] = []
        for offset in (0..<7).reversed() {
            let date = cal.date(byAdding: .day, value: -offset, to: Date())!
            let key = fmt.string(from: date)
            order.append(key)
            buckets[key] = 0
        }
        for session in weekSessions {
            let key = fmt.string(from: session.startedAt)
            buckets[key, default: 0] += Int(session.caloriesBurned ?? 0)
        }
        return order.map { DayData(day: $0, calories: buckets[$0] ?? 0) }
    }

    private var muscleCounts: [(muscle: String, count: Int)] {
        var counts: [String: Int] = [:]
        for session in weekSessions {
            for block in session.exercises {
                counts[block.exercise.primaryMuscle.rawValue, default: 0] += block.completedSetsCount
            }
        }
        return counts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    private func barRatio(_ count: Int) -> Double {
        let maxCount = muscleCounts.map { $0.count }.max() ?? 1
        return maxCount > 0 ? Double(count) / Double(maxCount) : 0
    }

    private var monthSessions: [WorkoutSession] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        return historyStore.sessions.filter { $0.startedAt >= cutoff && $0.isCompleted }
    }

    private struct MonthDayData { let day: Int; let calories: Int; let isCurrentWeek: Bool }

    private var monthlyData: [MonthDayData] {
        let cal = Calendar.current
        let today = Date()
        let weekAgo = cal.date(byAdding: .day, value: -7, to: today)!
        var buckets: [Int: Int] = [:]
        for session in monthSessions {
            let offset = cal.dateComponents([.day], from: session.startedAt, to: today).day ?? 0
            let key = 30 - offset
            buckets[key, default: 0] += Int(session.caloriesBurned ?? 0)
        }
        return (0..<30).map { i in
            MonthDayData(day: i, calories: buckets[i] ?? 0, isCurrentWeek: i >= 23)
        }
    }
}

struct StatsView_Previews: PreviewProvider {
    static var previews: some View {
        StatsView().preferredColorScheme(.dark)
    }
}
