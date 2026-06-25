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

    /// Search term yang lebih akurat untuk exercise lokal kita.
    /// (ExerciseDB tidak punya nama "plain" jadi kita arahkan ke istilah yang
    /// menghasilkan kandidat relevan, lalu scoring memilih yang paling cocok.)
    private static let curatedTerm: [String: String] = [
        "push-up": "push up", "bench press": "bench press", "chest fly": "dumbbell fly",
        "pull-up": "pull-up", "deadlift": "deadlift", "bent-over row": "bent over row",
        "squat": "squat", "lunge": "lunge", "leg press": "leg press",
        "shoulder press": "shoulder press", "lateral raise": "lateral raise",
        "bicep curl": "biceps curl", "tricep dip": "triceps dip",
        "plank": "front plank", "sit-up": "sit up",
        "running": "run", "jumping jacks": "jack", "burpee": "burpee",
        "mountain climbers": "mountain climber",
    ]

    private func resolve(name: String) async -> ExerciseDBResult? {
        let lower = name.lowercased()
        let term = Self.curatedTerm[lower] ?? lower

        var candidates = await fetchCandidates(term)
        if candidates.isEmpty {
            // Fallback: kata per kata
            let words = lower.replacingOccurrences(of: "-", with: " ")
                .split(separator: " ").map(String.init)
            for w in words where candidates.isEmpty {
                candidates = await fetchCandidates(w)
            }
        }
        guard !candidates.isEmpty else { return nil }

        // Pilih kandidat paling cocok dengan nama exercise kita
        let queryTokens = tokenize(name)
        let best = candidates.max { score($0, query: queryTokens) < score($1, query: queryTokens) }!

        return ExerciseDBResult(
            id: best.id, name: best.name, target: best.target,
            bodyPart: best.bodyPart, equipment: best.equipment,
            secondaryMuscles: best.secondaryMuscles ?? [],
            instructions: best.instructions ?? []
        )
    }

    private func fetchCandidates(_ term: String, limit: Int = 15) async -> [ExerciseDBRaw] {
        guard let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://\(host)/exercises/name/\(encoded)?limit=\(limit)&offset=0")
        else { return [] }
        var req = URLRequest(url: url)
        req.setValue(apiKey, forHTTPHeaderField: "X-RapidAPI-Key")
        req.setValue(host,   forHTTPHeaderField: "X-RapidAPI-Host")
        req.timeoutInterval = 15
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let raw = try? JSONDecoder().decode([ExerciseDBRaw].self, from: data)
        else { return [] }
        return raw
    }

    private func tokenize(_ s: String) -> Set<String> {
        Set(s.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ").map(String.init)
            .filter { $0.count > 2 || $0 == "up" })
    }

    /// Skor: overlap token (utama) − jumlah kata (lebih pendek = lebih generik)
    /// + bonus bodyweight (banyak exercise kita bodyweight).
    private func score(_ raw: ExerciseDBRaw, query: Set<String>) -> Int {
        let cTokens = tokenize(raw.name)
        let overlap = query.intersection(cTokens).count
        let wordCount = raw.name.split(separator: " ").count
        let bodyweightBonus = raw.equipment.lowercased().contains("body weight") ? 2 : 0
        return overlap * 10 - wordCount + bodyweightBonus
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
