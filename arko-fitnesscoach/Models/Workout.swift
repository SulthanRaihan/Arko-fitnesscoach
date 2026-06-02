import Foundation

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Exercise (cardio + strength catalog)
// ════════════════════════════════════════════════════════════════════════════

enum ExerciseType: String, Codable, CaseIterable {
    case strength
    case cardio
    case mobility
    case flexibility
}

enum MuscleGroup: String, Codable, CaseIterable {
    case chest, back, legs, shoulders, arms, core, fullBody
}

enum WorkoutIntensity: String, Codable, CaseIterable {
    case easy, moderate, hard

    var label: String {
        switch self {
        case .easy: return "Easy"
        case .moderate: return "Moderate"
        case .hard: return "Hard"
        }
    }
}

struct Exercise: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var type: ExerciseType
    var primaryMuscle: MuscleGroup
    var icon: String          // SF Symbol
    var instructions: String
    var supportsFormCheck: Bool   // bisa di-track dengan Vision
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Workout Set Log
// ════════════════════════════════════════════════════════════════════════════

/// Satu set yang sudah dilakukan / akan dilakukan
struct WorkoutSet: Codable, Identifiable, Hashable {
    let id: UUID
    var weight: Double?        // kg, nil untuk cardio
    var reps: Int?             // jumlah, nil untuk cardio
    var durationSeconds: Int?  // untuk cardio / plank
    var distanceMeters: Double? // untuk lari
    var completed: Bool

    init(weight: Double? = nil, reps: Int? = nil,
         durationSeconds: Int? = nil, distanceMeters: Double? = nil,
         completed: Bool = false) {
        self.id = UUID()
        self.weight = weight
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.completed = completed
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Exercise Block (exercise + sets-nya)
// ════════════════════════════════════════════════════════════════════════════

struct ExerciseBlock: Codable, Identifiable, Hashable {
    let id: UUID
    var exercise: Exercise
    var sets: [WorkoutSet]
    var restSeconds: Int       // istirahat antar set
    var notes: String?

    init(exercise: Exercise, sets: [WorkoutSet] = [], restSeconds: Int = 60, notes: String? = nil) {
        self.id = UUID()
        self.exercise = exercise
        self.sets = sets
        self.restSeconds = restSeconds
        self.notes = notes
    }

    var isCompleted: Bool {
        !sets.isEmpty && sets.allSatisfy { $0.completed }
    }

    var completedSetsCount: Int {
        sets.filter { $0.completed }.count
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Workout Template (reusable workout plan)
// ════════════════════════════════════════════════════════════════════════════

struct WorkoutTemplate: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var description: String
    var intensity: WorkoutIntensity
    var estimatedDurationMinutes: Int
    var estimatedCalories: Int
    var exercises: [ExerciseBlock]
    var icon: String           // SF Symbol
    var category: String       // "Strength", "Cardio", "Mixed"
    var imageName: String?     // Asset name in Assets.xcassets (optional)
    var accentColor: String?   // hex color for card gradient, e.g. "#FF6B35"
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Workout Session (active or completed)
// ════════════════════════════════════════════════════════════════════════════

struct WorkoutSession: Codable, Identifiable, Hashable {
    let id: UUID
    var templateId: String?    // jika dari template
    var name: String
    var startedAt: Date
    var completedAt: Date?
    var exercises: [ExerciseBlock]
    var notes: String?
    var caloriesBurned: Double?
    var aiRecommended: Bool

    init(template: WorkoutTemplate? = nil,
         name: String = "Workout",
         exercises: [ExerciseBlock] = [],
         aiRecommended: Bool = false) {
        self.id = UUID()
        self.templateId = template?.id
        self.name = template?.name ?? name
        self.startedAt = Date()
        self.completedAt = nil
        self.exercises = template?.exercises ?? exercises
        self.aiRecommended = aiRecommended
    }

    var durationMinutes: Int {
        let end = completedAt ?? Date()
        return Int(end.timeIntervalSince(startedAt) / 60)
    }

    var isCompleted: Bool {
        completedAt != nil
    }

    var completedExercisesCount: Int {
        exercises.filter { $0.isCompleted }.count
    }
}
