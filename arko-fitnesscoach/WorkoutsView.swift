import SwiftUI

// ════════════════════════════════════════════════════════════════════════════
// MARK: - WorkoutsView (Templates / Library / History tabs)
// ════════════════════════════════════════════════════════════════════════════

struct WorkoutsView: View {
    @State private var selectedTab: Tab = .templates
    @State private var activeSession: WorkoutSession?
    @State private var showProgram = false
    @State private var selectedExercise: Exercise?
    @StateObject private var historyStore = FirestoreWorkoutHistoryStore.shared

    enum Tab: String, CaseIterable {
        case templates = "Templates"
        case library   = "Exercises"
        case history   = "History"
    }

    var body: some View {
        ZStack {
            Color.arkoBg.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                tabSegmented
                ScrollView(showsIndicators: false) {
                    Group {
                        switch selectedTab {
                        case .templates: templatesList
                        case .library:   exerciseLibraryList
                        case .history:   historyList
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 100)
                }
            }
        }
        .fullScreenCover(item: $activeSession) { session in
            ActiveWorkoutView(session: session) { completed in
                Task {
                    try? await historyStore.saveSession(completed)
                    // Fire celebration + streak milestone notifications
                    let streak = computeStreak()
                    NotificationService.shared.sendWorkoutCompleteNotification(
                        workoutName: completed.name,
                        calories: Int(completed.caloriesBurned ?? 0),
                        streak: streak
                    )
                    NotificationService.shared.sendStreakMilestone(days: streak)
                }
                activeSession = nil
            } onCancel: {
                activeSession = nil
            }
        }
        .sheet(isPresented: $showProgram) {
            ProgramView()
        }
        .sheet(item: $selectedExercise) { ex in
            ExerciseDetailView(exercise: ex)
        }
    }

    // MARK: Top Bar

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Training").font(.caption).foregroundStyle(.secondary)
                Text("Workouts").font(.title2.weight(.bold))
            }
            Spacer()
            Button {
                showProgram = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text("AI Program")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.arkoLime)
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: Segmented Tabs

    private var tabSegmented: some View {
        HStack(spacing: 6) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.3)) { selectedTab = tab }
                } label: {
                    Text(tab.rawValue)
                        .font(.subheadline.weight(selectedTab == tab ? .bold : .medium))
                        .foregroundStyle(selectedTab == tab ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            selectedTab == tab ? Color.arkoTeal : Color.clear
                        )
                        .clipShape(Capsule())
                }
            }
        }
        .padding(4)
        .background(Color.arkoCard)
        .clipShape(Capsule())
        .padding(.horizontal, 20)
    }

    // MARK: Templates List

    private var templatesList: some View {
        VStack(spacing: 12) {
            ForEach(WorkoutTemplateLibrary.all) { template in
                TemplateCard(template: template) {
                    activeSession = WorkoutSession(template: template)
                }
            }
        }
    }

    // MARK: Exercise Library

    private var exerciseLibraryList: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionGroup(title: "Strength", icon: "dumbbell.fill",
                         exercises: ExerciseLibrary.strength)
            sectionGroup(title: "Cardio", icon: "flame.fill",
                         exercises: ExerciseLibrary.cardio)
            sectionGroup(title: "Mobility & Stretch", icon: "figure.mind.and.body",
                         exercises: ExerciseLibrary.mobility)
        }
    }

    private func sectionGroup(title: String, icon: String, exercises: [Exercise]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.arkoTeal)
            ForEach(exercises) { ex in
                ExerciseRow(exercise: ex) { selectedExercise = ex }
            }
        }
    }

    // MARK: History

    private var historyList: some View {
        VStack(spacing: 12) {
            if historyStore.sessions.isEmpty {
                emptyHistoryView
            } else {
                summaryCard
                ForEach(historyStore.sessions) { session in
                    HistoryCard(session: session)
                }
            }
        }
    }

    private var emptyHistoryView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No workout history yet")
                .font(.subheadline.weight(.semibold))
            Text("Complete your first workout to see it here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .arkoCard()
    }

    private var summaryCard: some View {
        HStack(spacing: 16) {
            statBox(value: "\(historyStore.sessions.count)", label: "Workouts")
            Divider().frame(height: 30)
            statBox(value: "\(totalMinutes())", label: "Minutes")
            Divider().frame(height: 30)
            statBox(value: "\(totalCalories())", label: "kcal")
        }
        .arkoCard(padding: 16)
    }

    private func computeStreak() -> Int {
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

    private func statBox(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.arkoTeal)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func totalMinutes() -> Int {
        historyStore.sessions.reduce(0) { $0 + $1.durationMinutes }
    }

    private func totalCalories() -> Int {
        Int(historyStore.sessions.reduce(0) { $0 + ($1.caloriesBurned ?? 0) })
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Template Card
// ════════════════════════════════════════════════════════════════════════════

private struct TemplateCard: View {
    let template: WorkoutTemplate
    let onStart: () -> Void

    var body: some View {
        Button(action: onStart) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(intensityColor(template.intensity).opacity(0.15))
                        .frame(width: 50, height: 50)
                    Image(systemName: template.icon)
                        .font(.system(size: 22))
                        .foregroundStyle(intensityColor(template.intensity))
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(template.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(template.category)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.arkoTeal.opacity(0.12))
                            .foregroundStyle(Color.arkoTeal)
                            .clipShape(Capsule())
                    }
                    Text("\(template.estimatedDurationMinutes) min · \(template.estimatedCalories) kcal · \(template.exercises.count) ex")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.arkoTeal)
            }
            .arkoCard(padding: 14)
        }
        .buttonStyle(.plain)
    }

    private func intensityColor(_ i: WorkoutIntensity) -> Color {
        switch i {
        case .easy: return Color.arkoGreen
        case .moderate: return Color.arkoTeal
        case .hard: return .orange
        }
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Exercise Row (library item)
// ════════════════════════════════════════════════════════════════════════════

private struct ExerciseRow: View {
    let exercise: Exercise
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button { onTap?() } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.arkoTeal.opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: exercise.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.arkoTeal)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(exercise.name)
                            .font(.subheadline.weight(.medium))
                        if exercise.supportsFormCheck {
                            Image(systemName: "camera.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(exercise.primaryMuscle.rawValue.capitalized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if onTap != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.arkoTextDim)
                }
            }
            .arkoCard(padding: 10)
        }
        .buttonStyle(.plain)
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - History Card
// ════════════════════════════════════════════════════════════════════════════

private struct HistoryCard: View {
    let session: WorkoutSession

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.arkoGreen.opacity(0.15))
                    .frame(width: 42, height: 42)
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.arkoGreen)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name).font(.subheadline.weight(.semibold))
                Text("\(session.durationMinutes) min · \(session.exercises.count) exercises")
                    .font(.caption).foregroundStyle(.secondary)
                Text(session.startedAt, style: .date)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .arkoCard(padding: 12)
    }
}

struct WorkoutsView_Previews: PreviewProvider {
    static var previews: some View {
        WorkoutsView()
    }
}
