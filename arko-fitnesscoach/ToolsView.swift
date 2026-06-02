import SwiftUI

// ════════════════════════════════════════════════════════════════════════════
// MARK: - ToolsView  (1RM Calculator + Rest Day Planner + Nutrition)
// Accessible from Profile tab or its own tab
// ════════════════════════════════════════════════════════════════════════════

struct ToolsView: View {
    var body: some View {
        ZStack {
            Color.arkoBg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header
                    nutritionLink
                    OneRMCalculatorCard()
                    RestDayPlannerCard()
                    Spacer(minLength: 110)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
        }
    }

    @State private var showNutrition = false

    private var nutritionLink: some View {
        Button { showNutrition = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 46, height: 46)
                    Image(systemName: "fork.knife")
                        .font(.system(size: 20))
                        .foregroundStyle(.green)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Nutrition Tracker")
                        .font(.subheadline.weight(.semibold))
                    Text("Log meals · Track macros · USDA database")
                        .font(.caption)
                        .foregroundStyle(Color.arkoTextDim)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.arkoTextDim)
            }
            .arkoCard(padding: 14)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showNutrition) { NutritionView() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fitness Tools").font(.caption).foregroundStyle(Color.arkoTextDim)
                Text("Tools").font(.title2.weight(.bold)).foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(.top, 8)
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - 1RM Calculator
// Epley formula: 1RM = weight × (1 + reps / 30)
// ════════════════════════════════════════════════════════════════════════════

struct OneRMCalculatorCard: View {
    @State private var weight: Double = 60
    @State private var reps: Double   = 10
    @State private var weightText = "60"
    @State private var repsText   = "10"

    private var oneRM: Double {
        let w = Double(weightText) ?? weight
        let r = Double(repsText)   ?? reps
        guard r > 0 else { return w }
        return w * (1 + r / 30)   // Epley formula
    }

    // Percentage table
    private let percentages: [(Int, String)] = [
        (100, "1 rep"),  (95, "2 reps"),  (90, "3 reps"),
        (85,  "4 reps"), (80, "5 reps"),  (75, "6 reps"),
        (70,  "8 reps"), (65, "10 reps"), (60, "12 reps"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("1RM Calculator", systemImage: "dumbbell.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.arkoLime)

            Text("Epley formula: weight × (1 + reps ÷ 30)")
                .font(.caption)
                .foregroundStyle(Color.arkoTextDim)

            // Inputs
            HStack(spacing: 16) {
                inputField(title: "Weight (kg)", text: $weightText, placeholder: "kg")
                inputField(title: "Reps done", text: $repsText, placeholder: "reps")
            }

            // Result
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Estimated 1RM")
                        .font(.caption)
                        .foregroundStyle(Color.arkoTextDim)
                    Text(String(format: "%.1f kg", oneRM))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.arkoLime)
                }
                Spacer()
                Image(systemName: "trophy.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.arkoLime.opacity(0.3))
            }
            .arkoCard(padding: 16)

            // Percentage table
            VStack(spacing: 0) {
                ForEach(percentages, id: \.0) { pct, label in
                    HStack {
                        Text("\(pct)%")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(pct == 100 ? Color.arkoLime : .white)
                            .frame(width: 44, alignment: .leading)
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(Color.arkoTextDim)
                        Spacer()
                        Text(String(format: "%.1f kg", oneRM * Double(pct) / 100))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.vertical, 6)
                    if pct != 60 {
                        Divider().background(Color.white.opacity(0.06))
                    }
                }
            }
            .padding(12)
            .background(Color.arkoCard2)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .arkoCard()
    }

    private func inputField(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption2).foregroundStyle(Color.arkoTextDim)
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .padding(12)
                .background(Color.arkoCard2)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity)
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Rest Day Planner
// Reads muscleLog and suggests which muscle groups need rest
// ════════════════════════════════════════════════════════════════════════════

struct RestDayPlannerCard: View {
    @StateObject private var muscleLog = MuscleLogService.shared

    private struct MuscleStatus: Identifiable {
        let id = UUID()
        let name: String
        let emoji: String
        let daysSince: Int?
        var status: RestStatus
        var suggestion: String
    }

    private enum RestStatus {
        case ready, recovering, needsRest
        var label: String {
            switch self { case .ready: return "Ready"; case .recovering: return "Recovering"; case .needsRest: return "Needs Rest" }
        }
        var color: Color {
            switch self { case .ready: return Color.arkoLime; case .recovering: return .orange; case .needsRest: return .red }
        }
    }

    private var muscleStatuses: [MuscleStatus] {
        let groups: [(String, String)] = [
            ("chest",     "💪"), ("back",      "🏋️"),
            ("shoulders", "🎯"), ("arms",      "💪"),
            ("legs",      "🦵"), ("core",      "🔥"),
        ]
        return groups.map { name, emoji in
            let days = muscleLog.daysSinceTrained(name)
            let status: RestStatus
            let suggestion: String
            switch days {
            case .none:
                status = .ready; suggestion = "Not trained recently — good to go!"
            case .some(let d) where d == 0:
                status = .needsRest; suggestion = "Trained today — rest this group."
            case .some(let d) where d <= 2:
                status = .recovering; suggestion = "Allow \(2 - (days ?? 0)) more day(s) to recover."
            default:
                status = .ready; suggestion = "Fully recovered — ready to train!"
            }
            return MuscleStatus(name: name.capitalized, emoji: emoji,
                                daysSince: days, status: status, suggestion: suggestion)
        }
    }

    private var todayRecommendation: String {
        let needsRest   = muscleStatuses.filter { $0.status == .needsRest }.map { $0.name }
        let ready       = muscleStatuses.filter { $0.status == .ready }.map { $0.name }

        if ready.isEmpty {
            return "Full rest or light mobility recommended today."
        }
        if needsRest.isEmpty {
            return "All muscle groups recovered! Great day for a full-body session."
        }
        return "Focus on \(ready.prefix(2).joined(separator: " & ")) today. Rest \(needsRest.first ?? "")."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Rest Day Planner", systemImage: "moon.zzz.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.arkoLime)

            // Today's recommendation
            HStack(spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
                Text(todayRecommendation)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Muscle group status grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(muscleStatuses) { ms in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(ms.emoji).font(.system(size: 18))
                            Spacer()
                            Text(ms.status.label)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(ms.status.color)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(ms.status.color.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        Text(ms.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(ms.daysSince.map { "\($0)d ago" } ?? "No data")
                            .font(.caption2)
                            .foregroundStyle(Color.arkoTextDim)
                    }
                    .padding(12)
                    .background(Color.arkoCard2)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .arkoCard()
        .task { await muscleLog.fetchLog() }
    }
}

struct ToolsView_Previews: PreviewProvider {
    static var previews: some View {
        ToolsView().preferredColorScheme(.dark)
    }
}
