import Foundation
import FirebaseFirestore
import FirebaseAuth

// ════════════════════════════════════════════════════════════════════════════
// MARK: - MuscleLogService
// Reads muscleLog collection and exposes the most-recent training date per
// muscle group. The data is written by FirestoreWorkoutHistoryStore on each
// completed workout save.
// ════════════════════════════════════════════════════════════════════════════

@MainActor
final class MuscleLogService: ObservableObject {
    static let shared = MuscleLogService()

    /// Maps MuscleGroup rawValue → most recent training date (within 30 days).
    @Published private(set) var muscleLastTrained: [String: Date] = [:]

    private let db = Firestore.firestore()

    private init() {}

    func fetchLog(days: Int = 30) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        do {
            let snap = try await db
                .collection("users").document(uid).collection("muscleLog")
                .whereField("ts", isGreaterThan: Timestamp(date: cutoff))
                .getDocuments()

            var result: [String: Date] = [:]
            for doc in snap.documents {
                guard let muscles = doc.data()["muscles"] as? [String],
                      let ts = doc.data()["ts"] as? Timestamp else { continue }
                let date = ts.dateValue()
                for muscle in muscles {
                    if let existing = result[muscle], existing >= date { continue }
                    result[muscle] = date
                }
            }
            muscleLastTrained = result
        } catch { }
    }

    /// Number of days since the muscle was last trained, or nil if no record.
    func daysSinceTrained(_ muscle: String) -> Int? {
        guard let last = muscleLastTrained[muscle] else { return nil }
        return Calendar.current.dateComponents([.day], from: last, to: Date()).day
    }
}
