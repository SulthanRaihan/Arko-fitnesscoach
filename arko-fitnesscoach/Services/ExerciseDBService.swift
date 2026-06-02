import Foundation

// ════════════════════════════════════════════════════════════════════════════
// MARK: - ExerciseDB Service (RapidAPI)
// Animated GIF + metadata for ~1300 exercises.
//
// SETUP (sekali saja):
//   1. Daftar gratis di https://rapidapi.com/justin-WFnsXH_t6/api/exercisedb
//   2. Subscribe ke "Basic" (free) plan
//   3. Copy "X-RapidAPI-Key" kamu, paste ke `apiKey` di bawah
//
// Free tier: cukup untuk dev/demo. Hasil di-cache per sesi.
// ════════════════════════════════════════════════════════════════════════════

struct ExerciseDBResult {
    let id: String
    let name: String
    let target: String          // primary muscle
    let bodyPart: String
    let equipment: String
    let secondaryMuscles: [String]
    let instructions: [String]
}

actor ExerciseDBService {
    static let shared = ExerciseDBService()

    // Key dibaca dari Secrets.swift (gitignored — tidak ikut ke GitHub)
    private let apiKey = Secrets.exerciseDBKey

    private let host = "exercisedb.p.rapidapi.com"
    private var cache: [String: ExerciseDBResult?] = [:]

    private init() {}

    var isConfigured: Bool { !apiKey.isEmpty }

    /// Search by exercise name, return the best match (with animated gifUrl).
    func lookup(_ exerciseName: String) async -> ExerciseDBResult? {
        guard isConfigured else { return nil }
        let key = exerciseName.lowercased()
        if let cached = cache[key] { return cached }

        let result = await resolve(name: exerciseName)
        cache[key] = result
        return result
    }

    /// Build an authenticated URLRequest for the exercise's animated GIF.
    /// (The image endpoint requires the RapidAPI headers, so AsyncImage can't
    /// load it directly — we hand back a ready-to-fetch request.)
    func gifRequest(for exerciseName: String, resolution: Int = 360) async -> URLRequest? {
        guard let result = await lookup(exerciseName) else { return nil }
        guard let url = URL(string: "https://\(host)/image?exerciseId=\(result.id)&resolution=\(resolution)")
        else { return nil }
        var req = URLRequest(url: url)
        req.setValue(apiKey, forHTTPHeaderField: "X-RapidAPI-Key")
        req.setValue(host,   forHTTPHeaderField: "X-RapidAPI-Host")
        req.timeoutInterval = 20
        return req
    }

    /// Browse exercises by target muscle (for the "By Muscle" feature).
    func exercises(forTarget target: String, limit: Int = 20) async -> [ExerciseDBResult] {
        guard isConfigured else { return [] }
        guard let encoded = target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://\(host)/exercises/target/\(encoded)?limit=\(limit)&offset=0")
        else { return [] }

        var req = URLRequest(url: url)
        req.setValue(apiKey, forHTTPHeaderField: "X-RapidAPI-Key")
        req.setValue(host,   forHTTPHeaderField: "X-RapidAPI-Host")
        req.timeoutInterval = 20

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let raw = try? JSONDecoder().decode([ExerciseDBRaw].self, from: data)
        else { return [] }

        return raw.map {
            ExerciseDBResult(id: $0.id, name: $0.name, target: $0.target,
                             bodyPart: $0.bodyPart, equipment: $0.equipment,
                             secondaryMuscles: $0.secondaryMuscles ?? [],
                             instructions: $0.instructions ?? [])
        }
    }

    /// Build an authenticated GIF request directly from an exercise id.
    func gifRequest(forId id: String, resolution: Int = 360) -> URLRequest? {
        guard !apiKey.isEmpty,
              let url = URL(string: "https://\(host)/image?exerciseId=\(id)&resolution=\(resolution)")
        else { return nil }
        var req = URLRequest(url: url)
        req.setValue(apiKey, forHTTPHeaderField: "X-RapidAPI-Key")
        req.setValue(host,   forHTTPHeaderField: "X-RapidAPI-Host")
        req.timeoutInterval = 20
        return req
    }

    // MARK: - Private

    private func resolve(name: String) async -> ExerciseDBResult? {
        // Try full name, then individual words (ExerciseDB does substring match)
        let words = name.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ").map(String.init)
        var terms = [name.lowercased()]
        if let first = words.first { terms.append(first) }
        if let last = words.last, last != words.first { terms.append(last) }

        for term in terms {
            if let hit = await search(term: term) { return hit }
        }
        return nil
    }

    private func search(term: String) async -> ExerciseDBResult? {
        guard let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://\(host)/exercises/name/\(encoded)?limit=5&offset=0")
        else { return nil }

        var req = URLRequest(url: url)
        req.setValue(apiKey, forHTTPHeaderField: "X-RapidAPI-Key")
        req.setValue(host,   forHTTPHeaderField: "X-RapidAPI-Host")
        req.timeoutInterval = 15

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let raw = try? JSONDecoder().decode([ExerciseDBRaw].self, from: data),
              let first = raw.first
        else { return nil }

        return ExerciseDBResult(
            id: first.id,
            name: first.name,
            target: first.target,
            bodyPart: first.bodyPart,
            equipment: first.equipment,
            secondaryMuscles: first.secondaryMuscles ?? [],
            instructions: first.instructions ?? []
        )
    }
}

// MARK: - Raw API model

private struct ExerciseDBRaw: Decodable {
    let id: String
    let name: String
    let target: String
    let bodyPart: String
    let equipment: String
    let secondaryMuscles: [String]?
    let instructions: [String]?
}
