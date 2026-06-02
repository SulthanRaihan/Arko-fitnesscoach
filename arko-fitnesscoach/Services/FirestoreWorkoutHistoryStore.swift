import Foundation
import FirebaseFirestore
import FirebaseAuth

// ════════════════════════════════════════════════════════════════════════════
// MARK: - FirestoreWorkoutHistoryStore
// ════════════════════════════════════════════════════════════════════════════

@MainActor
final class FirestoreWorkoutHistoryStore: WorkoutHistoryStoring, ObservableObject {
    static let shared = FirestoreWorkoutHistoryStore()

    private let db = Firestore.firestore()
    @Published var sessions: [WorkoutSession] = []

    private var uid: String? { Auth.auth().currentUser?.uid }

    private init() {
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            Task { @MainActor in
                if user != nil {
                    await self.loadAllSessions()
                } else {
                    self.sessions = []
                }
            }
        }
    }

    // MARK: - WorkoutHistoryStoring

    func saveSession(_ session: WorkoutSession) async throws {
        let ref = try workoutsRef()
        let data = try encodeSession(session)
        try await ref.document(session.id.uuidString).setData(data)
        await writeMuscleLog(for: session)
        _ = await loadAllSessions()
    }

    @discardableResult
    func loadAllSessions() async -> [WorkoutSession] {
        guard let ref = try? workoutsRef() else { return sessions }
        do {
            let snap = try await ref
                .order(by: "startedAt", descending: true)
                .getDocuments()
            let loaded = snap.documents.compactMap { decodeSession($0.data()) }
            sessions = loaded
            return loaded
        } catch {
            return sessions
        }
    }

    func deleteSession(id: UUID) async throws {
        let ref = try workoutsRef()
        try await ref.document(id.uuidString).delete()
        _ = await loadAllSessions()
    }

    func sessionsForDate(_ date: Date) async -> [WorkoutSession] {
        let cal = Calendar.current
        return sessions.filter { cal.isDate($0.startedAt, inSameDayAs: date) }
    }

    func recentSessions(limit: Int) async -> [WorkoutSession] {
        Array(sessions.prefix(limit))
    }

    // MARK: - Muscle Log

    private func writeMuscleLog(for session: WorkoutSession) async {
        guard let ref = try? muscleLogRef() else { return }
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: session.startedAt)
        guard let y = comps.year, let m = comps.month, let d = comps.day else { return }
        let dateKey = String(format: "%04d-%02d-%02d", y, m, d)
        let muscles = Array(Set(session.exercises.map { $0.exercise.primaryMuscle.rawValue }))
        guard !muscles.isEmpty else { return }
        do {
            try await ref.document(dateKey).setData([
                "muscles": FieldValue.arrayUnion(muscles),
                "ts": Timestamp(date: session.startedAt)
            ], merge: true)
        } catch { }
    }

    // MARK: - Firestore refs

    private func workoutsRef() throws -> CollectionReference {
        guard let uid else { throw StoreError.notAuthenticated }
        return db.collection("users").document(uid).collection("workouts")
    }

    private func muscleLogRef() throws -> CollectionReference {
        guard let uid else { throw StoreError.notAuthenticated }
        return db.collection("users").document(uid).collection("muscleLog")
    }

    // MARK: - Encode / Decode
    // Use JSON bridge because Firestore.Encoder struggles with nested UUID values.

    private func encodeSession(_ session: WorkoutSession) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let jsonData = try encoder.encode(session)
        guard var dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw StoreError.encodingFailed
        }
        // Replace Double epoch values with Firestore Timestamps so Firestore
        // can index them for range queries.
        if let secs = dict["startedAt"] as? Double {
            dict["startedAt"] = Timestamp(date: Date(timeIntervalSince1970: secs))
        }
        if let secs = dict["completedAt"] as? Double {
            dict["completedAt"] = Timestamp(date: Date(timeIntervalSince1970: secs))
        }
        return dict
    }

    private func decodeSession(_ data: [String: Any]) -> WorkoutSession? {
        var mutable = data
        if let ts = mutable["startedAt"] as? Timestamp {
            mutable["startedAt"] = ts.dateValue().timeIntervalSince1970
        }
        if let ts = mutable["completedAt"] as? Timestamp {
            mutable["completedAt"] = ts.dateValue().timeIntervalSince1970
        }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: mutable) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WorkoutSession.self, from: jsonData)
    }

    enum StoreError: Error {
        case notAuthenticated
        case encodingFailed
    }
}
