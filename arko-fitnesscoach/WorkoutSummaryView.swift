import SwiftUI

// ════════════════════════════════════════════════════════════════════════════
// MARK: - WorkoutSummaryView
// Shown after "Finish Workout" — displays stats, muscle heat map, exercise
// list. User must explicitly tap "Save Workout" to persist to Firestore.
// ════════════════════════════════════════════════════════════════════════════

struct WorkoutSummaryView: View {
    let session: WorkoutSession
    let onSave: () -> Void
    let onDiscard: () -> Void

    @State private var showDiscardAlert = false
    @State private var animateIn = false

    var body: some View {
        ZStack {
            Color.arkoBg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    completionBadge
                    statsRow
                    if !trainedMuscles.isEmpty { muscleMapCard }
                    exerciseListCard
                    actionButtons
                    Spacer(minLength: 60)
                }
                .padding(.horizontal, 24)
                .padding(.top, 36)
            }
        }
        .alert("Discard workout?", isPresented: $showDiscardAlert) {
            Button("Keep", role: .cancel) {}
            Button("Discard", role: .destructive) { onDiscard() }
        } message: {
            Text("This workout will not be saved.")
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1)) {
                animateIn = true
            }
        }
    }

    // MARK: - Completion badge

    private var completionBadge: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.arkoLime.opacity(0.14))
                    .frame(width: 88, height: 88)
                    .scaleEffect(animateIn ? 1 : 0.4)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.arkoLime)
                    .scaleEffect(animateIn ? 1 : 0.4)
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.6), value: animateIn)

            Text("Workout Complete!")
                .font(.title2.weight(.bold))
                .opacity(animateIn ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.25), value: animateIn)

            Text(session.name)
                .font(.subheadline)
                .foregroundStyle(Color.arkoTextDim)
                .opacity(animateIn ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.3), value: animateIn)
        }
    }

    // MARK: - Stats row

    private var statsRow: some View {
        HStack(spacing: 0) {
            statCell("\(session.durationMinutes)", unit: "min",
                     label: "Duration", icon: "clock.fill", color: Color.arkoLime)
            dividerLine
            statCell("\(completedSets)", unit: "/\(totalSets)",
                     label: "Sets Done", icon: "checkmark.square.fill", color: .cyan)
            dividerLine
            statCell("\(Int(session.caloriesBurned ?? 0))", unit: "kcal",
                     label: "Burned", icon: "flame.fill", color: .orange)
        }
        .arkoCard()
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 48)
    }

    private func statCell(_ value: String, unit: String, label: String,
                          icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.caption2).foregroundStyle(color)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(Color.arkoTextDim)
            }
            Text(label).font(.caption2).foregroundStyle(Color.arkoTextDim)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Muscle map

    private var muscleMapCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Muscles Trained", systemImage: "figure.arms.open")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.arkoLime)

            BodyMapView(muscleLastTrained: trainedMuscles)
                .frame(maxWidth: .infinity)
        }
        .arkoCard()
    }

    // MARK: - Exercise list

    private var exerciseListCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Exercises", systemImage: "list.bullet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.arkoLime)

            ForEach(session.exercises) { block in
                HStack(spacing: 10) {
                    Image(systemName: block.isCompleted
                          ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(block.isCompleted
                                         ? Color.arkoLime : Color.arkoTextDim)
                        .font(.system(size: 15))

                    Text(block.exercise.name)
                        .font(.subheadline)
                        .foregroundStyle(block.isCompleted ? .white : Color.arkoTextDim)

                    Spacer()

                    Text("\(block.completedSetsCount)/\(block.sets.count) sets")
                        .font(.caption)
                        .foregroundStyle(Color.arkoTextDim)
                }
            }
        }
        .arkoCard()
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button(action: onSave) {
                Text("Save Workout")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.arkoLime)
                    .clipShape(Capsule())
            }

            Button { showDiscardAlert = true } label: {
                Text("Discard")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.red.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
        }
    }

    // MARK: - Computed data

    private var trainedMuscles: [String: Date] {
        var result: [String: Date] = [:]
        for block in session.exercises where block.completedSetsCount > 0 {
            result[block.exercise.primaryMuscle.rawValue] = Date()
        }
        return result
    }

    private var completedSets: Int {
        session.exercises.reduce(0) { $0 + $1.completedSetsCount }
    }

    private var totalSets: Int {
        session.exercises.reduce(0) { $0 + $1.sets.count }
    }
}

struct WorkoutSummaryView_Previews: PreviewProvider {
    static var previews: some View {
        WorkoutSummaryView(
            session: WorkoutSession(template: WorkoutTemplateLibrary.pushDay),
            onSave: {},
            onDiscard: {}
        )
        .preferredColorScheme(.dark)
    }
}
