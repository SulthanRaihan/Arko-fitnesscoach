import Foundation

// ════════════════════════════════════════════════════════════════════════════
// MARK: - MuscleMapping
// Maps ExerciseDB's granular muscle names (target / secondaryMuscles) to ARKO's
// 7 body regions used by BodyMapView (chest, back, legs, shoulders, arms, core).
// ════════════════════════════════════════════════════════════════════════════

enum MuscleMapping {

    /// ExerciseDB target/secondary name → ARKO MuscleGroup rawValue
    static func region(for exerciseDBMuscle: String) -> String? {
        switch exerciseDBMuscle.lowercased() {
        case "pectorals", "serratus anterior":
            return "chest"
        case "lats", "upper back", "traps", "levator scapulae", "spine", "rhomboids":
            return "back"
        case "delts", "deltoids":
            return "shoulders"
        case "biceps", "triceps", "forearms":
            return "arms"
        case "quads", "hamstrings", "glutes", "calves", "abductors", "adductors":
            return "legs"
        case "abs":
            return "core"
        case "cardiovascular system":
            return "fullBody"
        default:
            return nil
        }
    }

    /// Map a list of ExerciseDB muscle names → unique ARKO regions
    static func regions(for muscles: [String]) -> Set<String> {
        Set(muscles.compactMap { region(for: $0) })
    }

    /// All ExerciseDB target muscles, grouped for the "Browse by Muscle" UI
    static let browseTargets: [(label: String, target: String, icon: String)] = [
        ("Chest",      "pectorals",  "figure.strengthtraining.traditional"),
        ("Lats/Back",  "lats",       "figure.strengthtraining.functional"),
        ("Upper Back", "upper back", "figure.strengthtraining.functional"),
        ("Shoulders",  "delts",      "figure.arms.open"),
        ("Biceps",     "biceps",     "dumbbell.fill"),
        ("Triceps",    "triceps",    "dumbbell.fill"),
        ("Forearms",   "forearms",   "dumbbell.fill"),
        ("Abs",        "abs",        "figure.core.training"),
        ("Quads",      "quads",      "figure.run"),
        ("Hamstrings", "hamstrings", "figure.run"),
        ("Glutes",     "glutes",     "figure.run"),
        ("Calves",     "calves",     "figure.walk"),
    ]
}
