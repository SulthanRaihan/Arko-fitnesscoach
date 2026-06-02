import SwiftUI

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Goal Definitions
// ════════════════════════════════════════════════════════════════════════════

struct FitnessGoal: Identifiable {
    let id: String          // backend goal key
    let title: String
    let subtitle: String
    let icon: String

    static let all: [FitnessGoal] = [
        FitnessGoal(id: "build_muscle", title: "Build Muscle",
                    subtitle: "Hypertrophy split, 8-12 reps", icon: "figure.strengthtraining.traditional"),
        FitnessGoal(id: "lose_weight", title: "Lose Weight",
                    subtitle: "Circuit + cardio, high reps", icon: "flame.fill"),
        FitnessGoal(id: "strength", title: "Get Stronger",
                    subtitle: "Heavy compounds, 3-5 reps", icon: "dumbbell.fill"),
        FitnessGoal(id: "endurance", title: "Endurance",
                    subtitle: "Cardio + conditioning", icon: "figure.run"),
    ]
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - ProgramView (goal selection → generate → days list)
// ════════════════════════════════════════════════════════════════════════════

struct ProgramView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var historyStore = FirestoreWorkoutHistoryStore.shared

    @State private var selectedGoal = "build_muscle"
    @State private var daysPerWeek = 4
    @State private var minutes = 45
    @State private var program: WorkoutProgramResponse?
    @State private var isLoading = false
    @State private var activeSession: WorkoutSession?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.arkoBg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        goalSection
                        controlsSection
                        generateButton
                        if let program = program {
                            programResult(program)
                        }
                        Spacer(minLength: 30)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("AI Program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .fullScreenCover(item: $activeSession) { session in
                ActiveWorkoutView(session: session) { completed in
                    Task { try? await historyStore.saveSession(completed) }
                    activeSession = nil
                } onCancel: {
                    activeSession = nil
                }
            }
        }
    }

    // MARK: Goal Selection

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What's your goal?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.arkoLime)
            ForEach(FitnessGoal.all) { goal in
                Button {
                    selectedGoal = goal.id
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedGoal == goal.id ? Color.arkoLime : Color.arkoCard2)
                                .frame(width: 44, height: 44)
                            Image(systemName: goal.icon)
                                .font(.system(size: 20))
                                .foregroundStyle(selectedGoal == goal.id ? .black : .white)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(goal.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                            Text(goal.subtitle).font(.caption).foregroundStyle(Color.arkoTextDim)
                        }
                        Spacer()
                        if selectedGoal == goal.id {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.arkoLime)
                        }
                    }
                    .padding(12)
                    .background(Color.arkoCard)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(selectedGoal == goal.id ? Color.arkoLime : Color.clear, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Controls

    private var controlsSection: some View {
        HStack(spacing: 12) {
            // Days per week
            VStack(alignment: .leading, spacing: 6) {
                Text("Days/week").font(.caption).foregroundStyle(Color.arkoTextDim)
                Menu {
                    ForEach(3...6, id: \.self) { d in
                        Button("\(d) days") { daysPerWeek = d }
                    }
                } label: {
                    pickerLabel("\(daysPerWeek) days", icon: "calendar")
                }
            }
            // Minutes
            VStack(alignment: .leading, spacing: 6) {
                Text("Per session").font(.caption).foregroundStyle(Color.arkoTextDim)
                Menu {
                    ForEach([30, 45, 60, 75], id: \.self) { m in
                        Button("\(m) min") { minutes = m }
                    }
                } label: {
                    pickerLabel("\(minutes) min", icon: "clock")
                }
            }
        }
    }

    private func pickerLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.subheadline.weight(.medium))
            Spacer()
            Image(systemName: "chevron.down").font(.caption2)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color.arkoCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Generate Button

    private var generateButton: some View {
        Button {
            Task { await generate() }
        } label: {
            HStack(spacing: 8) {
                if isLoading { ProgressView().tint(.black).scaleEffect(0.8) }
                else { Image(systemName: "sparkles") }
                Text(program == nil ? "Generate My Program" : "Regenerate")
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.arkoLime)
            .clipShape(Capsule())
        }
        .disabled(isLoading)
    }

    // MARK: Program Result

    private func programResult(_ program: WorkoutProgramResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(program.program_name)
                    .font(.title3.weight(.bold)).foregroundStyle(.white)
                Text("\(program.rep_range) · \(program.days_per_week) days/week")
                    .font(.caption).foregroundStyle(Color.arkoTextDim)
            }
            .padding(.top, 8)

            ForEach(program.days) { day in
                dayCard(day)
            }
        }
    }

    private func dayCard(_ day: ProgramDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    Circle().fill(Color.arkoLime).frame(width: 32, height: 32)
                    Text("\(day.day_number)").font(.caption.weight(.bold)).foregroundStyle(.black)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(day.name).font(.subheadline.weight(.bold)).foregroundStyle(.white)
                    Text("\(day.estimated_minutes) min · \(Int(day.estimated_calories)) kcal · \(day.exercises.count) ex")
                        .font(.caption2).foregroundStyle(Color.arkoTextDim)
                }
                Spacer()
                Button {
                    startDay(day)
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.arkoLime)
                }
            }
            // Exercise chips
            FlowChips(items: day.exercises.map { $0.name })
        }
        .arkoCard(padding: 14)
    }

    // MARK: Logic

    private func generate() async {
        isLoading = true
        do {
            let result = try await ARKOAPIService.shared.generateProgram(
                goal: selectedGoal, daysPerWeek: daysPerWeek, minutes: minutes
            )
            await MainActor.run { program = result; isLoading = false }
        } catch {
            await MainActor.run { isLoading = false }
        }
    }

    private func startDay(_ day: ProgramDay) {
        // Convert ProgramDay → WorkoutSession
        let blocks: [ExerciseBlock] = day.exercises.map { ex in
            let exercise = ExerciseLibrary.exercise(byId: ex.id)
                ?? Exercise(id: ex.id, name: ex.name, type: .strength,
                            primaryMuscle: .fullBody, icon: "figure.run",
                            instructions: "", supportsFormCheck: ex.supports_form_check)
            let sets = (0..<3).map { _ in WorkoutSet(reps: 10) }
            return ExerciseBlock(exercise: exercise, sets: sets, restSeconds: 60)
        }
        activeSession = WorkoutSession(name: day.name, exercises: blocks, aiRecommended: true)
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - FlowChips (wrap exercise names)
// ════════════════════════════════════════════════════════════════════════════

private struct FlowChips: View {
    let items: [String]

    var body: some View {
        // Simple wrap: max 2 baris pakai LazyVGrid adaptive
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.arkoCard2)
                    .foregroundStyle(.white.opacity(0.8))
                    .clipShape(Capsule())
            }
        }
    }
}

struct ProgramView_Previews: PreviewProvider {
    static var previews: some View {
        ProgramView().preferredColorScheme(.dark)
    }
}
