import Foundation

// Built-in exercise catalog — 25 exercises
// Mix of strength + cardio + mobility, semua bisa dipakai untuk template
enum ExerciseLibrary {

    static let all: [Exercise] = strength + cardio + mobility

    // MARK: - Strength (15)

    static let strength: [Exercise] = [
        // Chest
        Exercise(id: "ex_pushup",
                 name: "Push-up",
                 type: .strength,
                 primaryMuscle: .chest,
                 icon: "figure.strengthtraining.traditional",
                 instructions: "Keep body straight, lower until elbows reach 90°, push back up.",
                 supportsFormCheck: true),
        Exercise(id: "ex_bench_press",
                 name: "Bench Press",
                 type: .strength,
                 primaryMuscle: .chest,
                 icon: "dumbbell.fill",
                 instructions: "Lie flat, lower bar to chest, press up to full extension.",
                 supportsFormCheck: false),
        Exercise(id: "ex_chest_fly",
                 name: "Chest Fly",
                 type: .strength,
                 primaryMuscle: .chest,
                 icon: "dumbbell.fill",
                 instructions: "Arms slightly bent, lower dumbbells in arc motion, squeeze chest.",
                 supportsFormCheck: false),

        // Back
        Exercise(id: "ex_pullup",
                 name: "Pull-up",
                 type: .strength,
                 primaryMuscle: .back,
                 icon: "figure.strengthtraining.traditional",
                 instructions: "Hang from bar, pull chin above bar, control descent.",
                 supportsFormCheck: false),
        Exercise(id: "ex_deadlift",
                 name: "Deadlift",
                 type: .strength,
                 primaryMuscle: .back,
                 icon: "dumbbell.fill",
                 instructions: "Hinge at hips, keep back straight, lift bar by extending hips.",
                 supportsFormCheck: true),
        Exercise(id: "ex_row",
                 name: "Bent-over Row",
                 type: .strength,
                 primaryMuscle: .back,
                 icon: "dumbbell.fill",
                 instructions: "Hinge at hips, pull bar to lower chest, squeeze shoulder blades.",
                 supportsFormCheck: false),

        // Legs
        Exercise(id: "ex_squat",
                 name: "Squat",
                 type: .strength,
                 primaryMuscle: .legs,
                 icon: "figure.strengthtraining.functional",
                 instructions: "Feet shoulder-width, lower until thighs parallel to floor, drive up.",
                 supportsFormCheck: true),
        Exercise(id: "ex_lunge",
                 name: "Lunge",
                 type: .strength,
                 primaryMuscle: .legs,
                 icon: "figure.walk",
                 instructions: "Step forward, lower until both knees at 90°, push back to start.",
                 supportsFormCheck: true),
        Exercise(id: "ex_leg_press",
                 name: "Leg Press",
                 type: .strength,
                 primaryMuscle: .legs,
                 icon: "dumbbell.fill",
                 instructions: "Press platform away with feet, control return to start position.",
                 supportsFormCheck: false),

        // Shoulders
        Exercise(id: "ex_shoulder_press",
                 name: "Shoulder Press",
                 type: .strength,
                 primaryMuscle: .shoulders,
                 icon: "dumbbell.fill",
                 instructions: "Press dumbbells overhead, lower with control to shoulder height.",
                 supportsFormCheck: false),
        Exercise(id: "ex_lateral_raise",
                 name: "Lateral Raise",
                 type: .strength,
                 primaryMuscle: .shoulders,
                 icon: "dumbbell.fill",
                 instructions: "Raise dumbbells to shoulder height, slight bend in elbows.",
                 supportsFormCheck: false),

        // Arms
        Exercise(id: "ex_bicep_curl",
                 name: "Bicep Curl",
                 type: .strength,
                 primaryMuscle: .arms,
                 icon: "dumbbell.fill",
                 instructions: "Curl dumbbell to shoulder, keep elbows fixed, lower slowly.",
                 supportsFormCheck: true),
        Exercise(id: "ex_tricep_dip",
                 name: "Tricep Dip",
                 type: .strength,
                 primaryMuscle: .arms,
                 icon: "figure.strengthtraining.traditional",
                 instructions: "Lower body by bending elbows, push back up to start.",
                 supportsFormCheck: false),

        // Core
        Exercise(id: "ex_plank",
                 name: "Plank",
                 type: .strength,
                 primaryMuscle: .core,
                 icon: "figure.core.training",
                 instructions: "Hold straight line from shoulders to ankles, engage core.",
                 supportsFormCheck: true),
        Exercise(id: "ex_situp",
                 name: "Sit-up",
                 type: .strength,
                 primaryMuscle: .core,
                 icon: "figure.core.training",
                 instructions: "Lie on back, curl up to knees, lower with control.",
                 supportsFormCheck: false),
    ]

    // MARK: - Cardio (6)

    static let cardio: [Exercise] = [
        Exercise(id: "ex_running",
                 name: "Running",
                 type: .cardio,
                 primaryMuscle: .fullBody,
                 icon: "figure.run",
                 instructions: "Maintain steady pace, land mid-foot, keep upper body relaxed.",
                 supportsFormCheck: false),
        Exercise(id: "ex_walking",
                 name: "Brisk Walking",
                 type: .cardio,
                 primaryMuscle: .fullBody,
                 icon: "figure.walk",
                 instructions: "Walk at pace that elevates heart rate but allows conversation.",
                 supportsFormCheck: false),
        Exercise(id: "ex_cycling",
                 name: "Cycling",
                 type: .cardio,
                 primaryMuscle: .legs,
                 icon: "bicycle",
                 instructions: "Maintain steady cadence, adjust resistance to match intensity.",
                 supportsFormCheck: false),
        Exercise(id: "ex_jumping_jack",
                 name: "Jumping Jacks",
                 type: .cardio,
                 primaryMuscle: .fullBody,
                 icon: "figure.mixed.cardio",
                 instructions: "Jump, spreading legs and raising arms, return to start.",
                 supportsFormCheck: false),
        Exercise(id: "ex_burpee",
                 name: "Burpee",
                 type: .cardio,
                 primaryMuscle: .fullBody,
                 icon: "figure.mixed.cardio",
                 instructions: "Squat, plank, push-up, jump back up. Full body movement.",
                 supportsFormCheck: false),
        Exercise(id: "ex_mountain_climber",
                 name: "Mountain Climbers",
                 type: .cardio,
                 primaryMuscle: .core,
                 icon: "figure.mixed.cardio",
                 instructions: "Plank position, alternate driving knees toward chest rapidly.",
                 supportsFormCheck: false),
    ]

    // MARK: - Mobility / Flexibility (4)

    static let mobility: [Exercise] = [
        Exercise(id: "ex_stretch_hamstring",
                 name: "Hamstring Stretch",
                 type: .flexibility,
                 primaryMuscle: .legs,
                 icon: "figure.flexibility",
                 instructions: "Sit, extend one leg, reach toward toes, hold without bouncing.",
                 supportsFormCheck: false),
        Exercise(id: "ex_stretch_quad",
                 name: "Quad Stretch",
                 type: .flexibility,
                 primaryMuscle: .legs,
                 icon: "figure.flexibility",
                 instructions: "Stand, pull heel to glutes, keep knees together.",
                 supportsFormCheck: false),
        Exercise(id: "ex_yoga_flow",
                 name: "Yoga Flow",
                 type: .mobility,
                 primaryMuscle: .fullBody,
                 icon: "figure.mind.and.body",
                 instructions: "Sun salutation sequence, focus on breath and form.",
                 supportsFormCheck: false),
        Exercise(id: "ex_foam_roll",
                 name: "Foam Rolling",
                 type: .mobility,
                 primaryMuscle: .fullBody,
                 icon: "figure.cooldown",
                 instructions: "Roll slowly over tight muscle groups, breathe through tension.",
                 supportsFormCheck: false),
    ]

    // MARK: - Lookup helpers

    static func exercise(byId id: String) -> Exercise? {
        all.first { $0.id == id }
    }

    static func exercises(for muscle: MuscleGroup) -> [Exercise] {
        all.filter { $0.primaryMuscle == muscle }
    }

    static func exercises(for type: ExerciseType) -> [Exercise] {
        all.filter { $0.type == type }
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Default Workout Templates (3 default + extras)
// ════════════════════════════════════════════════════════════════════════════

enum WorkoutTemplateLibrary {

    static let all: [WorkoutTemplate] = [pushDay, pullDay, legDay, fullBody, hiitCardio, mobility]

    // 3 sets, 8-12 reps default untuk strength
    private static func block(_ exerciseId: String, sets: Int = 3, reps: Int = 10, rest: Int = 60) -> ExerciseBlock {
        guard let ex = ExerciseLibrary.exercise(byId: exerciseId) else {
            return ExerciseBlock(exercise: ExerciseLibrary.strength[0])
        }
        let setLogs = (0..<sets).map { _ in WorkoutSet(weight: nil, reps: reps) }
        return ExerciseBlock(exercise: ex, sets: setLogs, restSeconds: rest)
    }

    private static func cardioBlock(_ exerciseId: String, durationMin: Int) -> ExerciseBlock {
        guard let ex = ExerciseLibrary.exercise(byId: exerciseId) else {
            return ExerciseBlock(exercise: ExerciseLibrary.cardio[0])
        }
        return ExerciseBlock(
            exercise: ex,
            sets: [WorkoutSet(durationSeconds: durationMin * 60)],
            restSeconds: 30
        )
    }

    // MARK: Push Day

    static let pushDay = WorkoutTemplate(
        id: "tpl_push",
        name: "Push Day",
        description: "Chest, shoulders, triceps focus.",
        intensity: .moderate,
        estimatedDurationMinutes: 45,
        estimatedCalories: 280,
        exercises: [
            block("ex_bench_press"),
            block("ex_shoulder_press"),
            block("ex_chest_fly"),
            block("ex_lateral_raise"),
            block("ex_tricep_dip"),
            block("ex_pushup", sets: 2, reps: 12),
        ],
        icon: "figure.strengthtraining.traditional",
        category: "Strength"
    )

    // MARK: Pull Day

    static let pullDay = WorkoutTemplate(
        id: "tpl_pull",
        name: "Pull Day",
        description: "Back and biceps focus.",
        intensity: .moderate,
        estimatedDurationMinutes: 45,
        estimatedCalories: 270,
        exercises: [
            block("ex_pullup", sets: 3, reps: 8),
            block("ex_deadlift", sets: 3, reps: 6, rest: 90),
            block("ex_row"),
            block("ex_bicep_curl"),
        ],
        icon: "figure.strengthtraining.traditional",
        category: "Strength"
    )

    // MARK: Leg Day

    static let legDay = WorkoutTemplate(
        id: "tpl_legs",
        name: "Leg Day",
        description: "Quads, hamstrings, glutes.",
        intensity: .hard,
        estimatedDurationMinutes: 50,
        estimatedCalories: 350,
        exercises: [
            block("ex_squat", sets: 4, reps: 8, rest: 90),
            block("ex_lunge", sets: 3, reps: 10),
            block("ex_leg_press"),
            block("ex_stretch_hamstring", sets: 1, reps: 1),
        ],
        icon: "figure.strengthtraining.functional",
        category: "Strength"
    )

    // MARK: Full Body

    static let fullBody = WorkoutTemplate(
        id: "tpl_full",
        name: "Full Body",
        description: "Hit all major muscle groups in one session.",
        intensity: .moderate,
        estimatedDurationMinutes: 40,
        estimatedCalories: 320,
        exercises: [
            block("ex_squat"),
            block("ex_pushup", sets: 3, reps: 12),
            block("ex_row"),
            block("ex_plank", sets: 3, reps: 1),
        ],
        icon: "figure.mixed.cardio",
        category: "Strength"
    )

    // MARK: HIIT Cardio

    static let hiitCardio = WorkoutTemplate(
        id: "tpl_hiit",
        name: "HIIT Cardio",
        description: "High-intensity intervals for calorie burn.",
        intensity: .hard,
        estimatedDurationMinutes: 25,
        estimatedCalories: 280,
        exercises: [
            cardioBlock("ex_jumping_jack", durationMin: 1),
            cardioBlock("ex_burpee", durationMin: 1),
            cardioBlock("ex_mountain_climber", durationMin: 1),
            cardioBlock("ex_jumping_jack", durationMin: 1),
            cardioBlock("ex_burpee", durationMin: 1),
        ],
        icon: "flame.fill",
        category: "Cardio"
    )

    // MARK: Mobility

    static let mobility = WorkoutTemplate(
        id: "tpl_mobility",
        name: "Recovery & Mobility",
        description: "Light stretching and yoga flow.",
        intensity: .easy,
        estimatedDurationMinutes: 20,
        estimatedCalories: 90,
        exercises: [
            cardioBlock("ex_yoga_flow", durationMin: 10),
            cardioBlock("ex_stretch_hamstring", durationMin: 2),
            cardioBlock("ex_stretch_quad", durationMin: 2),
            cardioBlock("ex_foam_roll", durationMin: 5),
        ],
        icon: "figure.mind.and.body",
        category: "Recovery"
    )
}
