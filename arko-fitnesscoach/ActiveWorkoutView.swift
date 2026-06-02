import SwiftUI

// ════════════════════════════════════════════════════════════════════════════
// MARK: - ActiveWorkoutView (in-progress workout)
// ════════════════════════════════════════════════════════════════════════════

struct ActiveWorkoutView: View {
    @State var session: WorkoutSession
    let onComplete: (WorkoutSession) -> Void
    let onCancel: () -> Void

    @State private var currentExerciseIndex: Int = 0
    @State private var restRemaining: Int = 0
    @State private var restTimer: Timer?
    @State private var showCancelAlert = false
    @State private var showFormCheck = false
    @State private var summarySession: WorkoutSession?

    private var currentBlock: ExerciseBlock? {
        guard session.exercises.indices.contains(currentExerciseIndex) else { return nil }
        return session.exercises[currentExerciseIndex]
    }

    var body: some View {
        ZStack {
            Color.arkoBg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                progressBar
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        if let block = currentBlock {
                            currentExerciseCard(block: block)
                            setsLoggerSection(block: block)
                        }
                        if restRemaining > 0 { restTimerCard }
                        exerciseListSection
                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
                bottomActionBar
            }
        }
        .alert("End workout?", isPresented: $showCancelAlert) {
            Button("Keep going", role: .cancel) {}
            Button("End", role: .destructive) {
                stopRestTimer()
                onCancel()
            }
        } message: {
            Text("Your progress will not be saved.")
        }
        .fullScreenCover(isPresented: $showFormCheck) {
            if let block = currentBlock {
                FormCheckView(
                    presetExercise: formCheckName(for: block.exercise),
                    onFinish: { reps in
                        applyFormCheckReps(reps, toBlock: currentExerciseIndex)
                    }
                )
            }
        }
        .fullScreenCover(item: $summarySession) { completed in
            WorkoutSummaryView(
                session: completed,
                onSave: {
                    summarySession = nil
                    onComplete(completed)
                },
                onDiscard: {
                    summarySession = nil
                    onCancel()
                }
            )
        }
    }

    /// Map exercise name ke nama yang dikenal RepCounter (ExerciseConfig.all)
    private func formCheckName(for exercise: Exercise) -> String {
        let n = exercise.name.lowercased()
        if n.contains("squat") { return "Squat" }
        if n.contains("push")  { return "Push-up" }
        if n.contains("deadlift") { return "Deadlift" }
        if n.contains("lunge") { return "Lunge" }
        if n.contains("plank") { return "Plank" }
        return "Squat"
    }

    /// Isi set pertama yang belum complete dengan rep count dari Form Check
    private func applyFormCheckReps(_ reps: Int, toBlock blockIndex: Int) {
        guard reps > 0 else { return }
        var blocks = session.exercises
        guard blocks.indices.contains(blockIndex) else { return }
        if let setIdx = blocks[blockIndex].sets.firstIndex(where: { !$0.completed }) {
            blocks[blockIndex].sets[setIdx].reps = reps
            blocks[blockIndex].sets[setIdx].completed = true
            session.exercises = blocks
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button {
                showCancelAlert = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color.arkoCard)
                    .clipShape(Circle())
            }
            Spacer()
            VStack(spacing: 2) {
                Text(session.name)
                    .font(.subheadline.weight(.bold))
                Text(durationText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            // placeholder symmetric
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var progressBar: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Exercise \(currentExerciseIndex + 1) of \(session.exercises.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(completedSetsTotal)/\(totalSets) sets")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.arkoTeal)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.15))
                    Capsule()
                        .fill(LinearGradient(colors: [Color.arkoTeal, .blue],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * progressFraction)
                        .animation(.spring(response: 0.4), value: progressFraction)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    // MARK: Current Exercise Card

    private func currentExerciseCard(block: ExerciseBlock) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.arkoTeal.opacity(0.15))
                    .frame(width: 56, height: 56)
                Image(systemName: block.exercise.icon)
                    .font(.system(size: 26))
                    .foregroundStyle(Color.arkoTeal)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(block.exercise.name)
                    .font(.headline)
                Text(block.exercise.primaryMuscle.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if block.exercise.supportsFormCheck {
                Button {
                    showFormCheck = true
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Form").font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .arkoCard()
    }

    // MARK: Sets Logger

    private func setsLoggerSection(block: ExerciseBlock) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("Sets")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Rest \(block.restSeconds)s")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(block.sets.enumerated()), id: \.element.id) { idx, set in
                SetRow(
                    setNumber: idx + 1,
                    set: set,
                    exerciseType: block.exercise.type,
                    onToggle: { toggleSet(blockIndex: currentExerciseIndex, setIndex: idx, restSeconds: block.restSeconds) },
                    onWeightChange: { newVal in updateSet(blockIndex: currentExerciseIndex, setIndex: idx) { $0.weight = newVal } },
                    onRepsChange: { newVal in updateSet(blockIndex: currentExerciseIndex, setIndex: idx) { $0.reps = newVal } },
                    onDurationChange: { newVal in updateSet(blockIndex: currentExerciseIndex, setIndex: idx) { $0.durationSeconds = newVal } }
                )
            }
        }
        .arkoCard()
    }

    // MARK: Rest Timer Card

    private var restTimerCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color.orange.opacity(0.2), lineWidth: 4)
                    .frame(width: 50, height: 50)
                Text("\(restRemaining)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Resting").font(.subheadline.weight(.semibold))
                Text("Take a breath and prepare for next set")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Skip") {
                stopRestTimer()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
        }
        .arkoCard()
    }

    // MARK: Exercise List

    private var exerciseListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("All Exercises")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(session.exercises.enumerated()), id: \.element.id) { idx, block in
                Button {
                    currentExerciseIndex = idx
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: block.isCompleted ? "checkmark.circle.fill" :
                                idx == currentExerciseIndex ? "circle.dashed" : "circle")
                            .foregroundStyle(block.isCompleted ? Color.arkoGreen :
                                idx == currentExerciseIndex ? Color.arkoTeal : .secondary)
                        Text(block.exercise.name)
                            .font(.subheadline)
                            .foregroundStyle(idx == currentExerciseIndex ? .primary : .secondary)
                        Spacer()
                        Text("\(block.completedSetsCount)/\(block.sets.count)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(idx == currentExerciseIndex ? Color.arkoTeal.opacity(0.08) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color.arkoCard)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: Bottom Bar

    private var bottomActionBar: some View {
        HStack(spacing: 10) {
            Button {
                if currentExerciseIndex > 0 { currentExerciseIndex -= 1 }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 50, height: 50)
                    .background(Color.arkoCard)
                    .clipShape(Circle())
            }
            .disabled(currentExerciseIndex == 0)
            .opacity(currentExerciseIndex == 0 ? 0.4 : 1)

            if currentExerciseIndex < session.exercises.count - 1 {
                Button {
                    currentExerciseIndex += 1
                } label: {
                    Text("Next Exercise")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.arkoTeal)
                        .clipShape(Capsule())
                }
            } else {
                Button {
                    finishWorkout()
                } label: {
                    Text("Finish Workout")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(LinearGradient(colors: [Color.arkoGreen, .green],
                                                   startPoint: .leading, endPoint: .trailing))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: Helpers

    private var totalSets: Int {
        session.exercises.reduce(0) { $0 + $1.sets.count }
    }

    private var completedSetsTotal: Int {
        session.exercises.reduce(0) { $0 + $1.completedSetsCount }
    }

    private var progressFraction: Double {
        guard totalSets > 0 else { return 0 }
        return Double(completedSetsTotal) / Double(totalSets)
    }

    private var durationText: String {
        let secs = Int(Date().timeIntervalSince(session.startedAt))
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }

    // MARK: Mutations

    private func toggleSet(blockIndex: Int, setIndex: Int, restSeconds: Int) {
        var blocks = session.exercises
        guard blocks.indices.contains(blockIndex),
              blocks[blockIndex].sets.indices.contains(setIndex) else { return }
        blocks[blockIndex].sets[setIndex].completed.toggle()
        session.exercises = blocks
        // Mulai rest timer kalau set baru selesai
        if blocks[blockIndex].sets[setIndex].completed {
            startRestTimer(seconds: restSeconds)
        }
    }

    private func updateSet(blockIndex: Int, setIndex: Int, mutation: (inout WorkoutSet) -> Void) {
        var blocks = session.exercises
        guard blocks.indices.contains(blockIndex),
              blocks[blockIndex].sets.indices.contains(setIndex) else { return }
        mutation(&blocks[blockIndex].sets[setIndex])
        session.exercises = blocks
    }

    private func startRestTimer(seconds: Int) {
        stopRestTimer()
        restRemaining = seconds
        restTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            if restRemaining > 0 {
                restRemaining -= 1
            } else {
                t.invalidate()
            }
        }
    }

    private func stopRestTimer() {
        restTimer?.invalidate()
        restTimer = nil
        restRemaining = 0
    }

    private func finishWorkout() {
        stopRestTimer()
        var completed = session
        completed.completedAt = Date()
        let mins = Double(completed.durationMinutes)
        completed.caloriesBurned = mins * 6  // ~6 kcal/min estimate
        summarySession = completed
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Set Row
// ════════════════════════════════════════════════════════════════════════════

private struct SetRow: View {
    let setNumber: Int
    let set: WorkoutSet
    let exerciseType: ExerciseType
    let onToggle: () -> Void
    let onWeightChange: (Double?) -> Void
    let onRepsChange: (Int?) -> Void
    let onDurationChange: (Int?) -> Void

    @State private var weightText: String = ""
    @State private var repsText: String = ""
    @State private var durationText: String = ""

    var body: some View {
        HStack(spacing: 10) {
            // Set number badge
            Text("\(setNumber)")
                .font(.caption.weight(.bold))
                .foregroundStyle(set.completed ? .white : Color.arkoTeal)
                .frame(width: 28, height: 28)
                .background(set.completed ? Color.arkoTeal : Color.arkoTeal.opacity(0.12))
                .clipShape(Circle())

            // Input fields per type
            if exerciseType == .cardio || exerciseType == .mobility || exerciseType == .flexibility {
                TextField("0", text: $durationText)
                    .keyboardType(.numberPad)
                    .frame(maxWidth: .infinity)
                    .onChange(of: durationText) { v in
                        onDurationChange(Int(v).map { $0 * 60 } ?? nil)
                    }
                Text("sec").font(.caption).foregroundStyle(.secondary)
            } else {
                TextField("kg", text: $weightText)
                    .keyboardType(.decimalPad)
                    .frame(maxWidth: .infinity)
                    .onChange(of: weightText) { v in
                        onWeightChange(Double(v))
                    }
                Text("×").foregroundStyle(.secondary)
                TextField("reps", text: $repsText)
                    .keyboardType(.numberPad)
                    .frame(maxWidth: .infinity)
                    .onChange(of: repsText) { v in
                        onRepsChange(Int(v))
                    }
            }

            // Checkbox
            Button(action: onToggle) {
                Image(systemName: set.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(set.completed ? Color.arkoGreen : .secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(set.completed ? Color.arkoGreen.opacity(0.08) : Color.gray.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear {
            if let w = set.weight { weightText = String(format: "%g", w) }
            if let r = set.reps { repsText = "\(r)" }
            if let d = set.durationSeconds { durationText = "\(d/60)" }
        }
    }
}

struct ActiveWorkoutView_Previews: PreviewProvider {
    static var previews: some View {
        ActiveWorkoutView(
            session: WorkoutSession(template: WorkoutTemplateLibrary.pushDay),
            onComplete: { _ in },
            onCancel: {}
        )
    }
}
