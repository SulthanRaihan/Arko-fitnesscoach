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
        case byMuscle  = "By Muscle"
        case history   = "History"
    }

    var body: some View {
        ZStack {
            Color.arkoBg.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                tabSegmented
                if selectedTab == .byMuscle {
                    // MuscleBrowseView manages its own scrolling
                    MuscleBrowseView()
                        .padding(.top, 12)
                } else {
                    ScrollView(showsIndicators: false) {
                        Group {
                            switch selectedTab {
                            case .templates: templatesList
                            case .library:   exerciseLibraryList
                            case .history:   historyList
                            case .byMuscle:  EmptyView()
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .padding(.bottom, 100)
                    }
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
        .padding(.horizontal, 24)
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
        .padding(.horizontal, 24)
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

    /// Build a quick single-exercise session (3 sets) for the Play button.
    private func singleExerciseSession(_ ex: Exercise) -> WorkoutSession {
        let isTimed = ex.type == .cardio || ex.type == .mobility || ex.type == .flexibility
        let sets: [WorkoutSet] = (0..<3).map { _ in
            isTimed ? WorkoutSet(durationSeconds: 60) : WorkoutSet(weight: nil, reps: 10)
        }
        let block = ExerciseBlock(exercise: ex, sets: sets, restSeconds: 60)
        return WorkoutSession(name: ex.name, exercises: [block])
    }

    private func sectionGroup(title: String, icon: String, exercises: [Exercise]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.arkoTeal)
            ForEach(exercises) { ex in
                ExerciseRow(
                    exercise: ex,
                    onTap:  { selectedExercise = ex },
                    onPlay: { activeSession = singleExerciseSession(ex) }
                )
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

    private var accent: Color {
        guard let hex = template.accentColor else { return Color.arkoTeal }
        return Color(hex: hex) ?? Color.arkoTeal
    }

    var body: some View {
        Button(action: onStart) {
            ZStack(alignment: .bottomLeading) {
                // Background: photo or gradient
                if let imgName = template.imageName, UIImage(named: imgName) != nil {
                    GeometryReader { geo in
                        Image(imgName)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    }
                    .frame(height: 160)
                    // Dark gradient overlay for readability
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.75)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 160)
                } else {
                    // Fallback gradient card
                    LinearGradient(
                        colors: [accent.opacity(0.8), accent.opacity(0.4)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .frame(height: 160)
                    // Icon placeholder
                    HStack {
                        Spacer()
                        Image(systemName: template.icon)
                            .font(.system(size: 64))
                            .foregroundStyle(.white.opacity(0.15))
                            .padding(.trailing, 24)
                            .padding(.top, 20)
                    }
                }

                // Content overlay
                VStack(alignment: .leading, spacing: 6) {
                    // Category badge
                    HStack(spacing: 6) {
                        Text(template.category.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.45))
                            .clipShape(Capsule())
                        Spacer()
                        // Intensity badge
                        Text(template.intensity.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(intensityColor(template.intensity).opacity(0.7))
                            .clipShape(Capsule())
                    }

                    Spacer()

                    // Title + stats
                    VStack(alignment: .leading, spacing: 4) {
                        Text(template.name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)

                        HStack(spacing: 14) {
                            statBadge(icon: "clock", text: "\(template.estimatedDurationMinutes) min")
                            statBadge(icon: "flame.fill", text: "\(template.estimatedCalories) kcal")
                            statBadge(icon: "dumbbell.fill", text: "\(template.exercises.count) exercises")
                        }
                    }
                }
                .padding(14)
                .frame(height: 160, alignment: .bottom)

                // Play button
                VStack {
                    HStack {
                        Spacer()
                        Circle()
                            .fill(.white.opacity(0.2))
                            .frame(width: 42, height: 42)
                            .overlay(
                                Image(systemName: "play.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                            )
                            .padding(14)
                    }
                    Spacer()
                }
                .frame(height: 160)
            }
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    private func statBadge(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(.caption2.weight(.medium))
        }
        .foregroundStyle(.white.opacity(0.85))
    }

    private func intensityColor(_ i: WorkoutIntensity) -> Color {
        switch i {
        case .easy:     return .green
        case .moderate: return .orange
        case .hard:     return .red
        }
    }
}

// MARK: - Color hex extension

extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        self.init(
            red:   Double((val >> 16) & 0xFF) / 255,
            green: Double((val >>  8) & 0xFF) / 255,
            blue:  Double( val        & 0xFF) / 255
        )
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Exercise Thumbnail (WGER image with icon fallback + cache)
// ════════════════════════════════════════════════════════════════════════════

private struct ExerciseThumbnail: View {
    let exercise: Exercise

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white)
            ExerciseGIFView(exercise: exercise, resolution: 180)
                .padding(3)
        }
        .frame(width: 46, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Exercise Row (library item)
// ════════════════════════════════════════════════════════════════════════════

private struct ExerciseRow: View {
    let exercise: Exercise
    var onTap: (() -> Void)? = nil
    var onPlay: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Tappable area → detail
            Button { onTap?() } label: {
                HStack(spacing: 12) {
                    ExerciseThumbnail(exercise: exercise)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(exercise.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
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
                }
            }
            .buttonStyle(.plain)

            // Play button → start single-exercise session
            Button { onPlay?() } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 34, height: 34)
                    .background(Color.arkoLime)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .arkoCard(padding: 10)
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
