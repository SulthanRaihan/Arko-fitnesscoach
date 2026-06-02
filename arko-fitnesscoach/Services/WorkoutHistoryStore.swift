import Foundation
import Combine

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Storage Protocol (swappable: UserDefaults → Firebase nanti)
// ════════════════════════════════════════════════════════════════════════════

protocol WorkoutHistoryStoring {
    func saveSession(_ session: WorkoutSession) async throws
    func loadAllSessions() async -> [WorkoutSession]
    func deleteSession(id: UUID) async throws
    func sessionsForDate(_ date: Date) async -> [WorkoutSession]
    func recentSessions(limit: Int) async -> [WorkoutSession]
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - UserDefaults Implementation
// ════════════════════════════════════════════════════════════════════════════

final class UserDefaultsWorkoutHistoryStore: WorkoutHistoryStoring, ObservableObject {
    static let shared = UserDefaultsWorkoutHistoryStore()

    private let key = "arko_workout_sessions"
    private let defaults = UserDefaults.standard

    @Published var sessions: [WorkoutSession] = []

    private init() {
        Task { await reload() }
    }

    // MARK: Public API

    func saveSession(_ session: WorkoutSession) async throws {
        var current = loadFromDefaults()
        if let idx = current.firstIndex(where: { $0.id == session.id }) {
            current[idx] = session
        } else {
            current.append(session)
        }
        try writeToDefaults(current)
        let sorted = current.sorted { $0.startedAt > $1.startedAt }
        await MainActor.run { self.sessions = sorted }
    }

    func loadAllSessions() async -> [WorkoutSession] {
        loadFromDefaults().sorted { $0.startedAt > $1.startedAt }
    }

    func deleteSession(id: UUID) async throws {
        var current = loadFromDefaults()
        current.removeAll { $0.id == id }
        try writeToDefaults(current)
        let sorted = current.sorted { $0.startedAt > $1.startedAt }
        await MainActor.run { self.sessions = sorted }
    }

    func sessionsForDate(_ date: Date) async -> [WorkoutSession] {
        let cal = Calendar.current
        return loadFromDefaults().filter {
            cal.isDate($0.startedAt, inSameDayAs: date)
        }
    }

    func recentSessions(limit: Int) async -> [WorkoutSession] {
        Array(loadFromDefaults().sorted { $0.startedAt > $1.startedAt }.prefix(limit))
    }

    // MARK: Private

    private func loadFromDefaults() -> [WorkoutSession] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([WorkoutSession].self, from: data)) ?? []
    }

    private func writeToDefaults(_ sessions: [WorkoutSession]) throws {
        let data = try JSONEncoder().encode(sessions)
        defaults.set(data, forKey: key)
    }

    @MainActor
    func reload() {
        self.sessions = loadFromDefaults().sorted { $0.startedAt > $1.startedAt }
    }
}
