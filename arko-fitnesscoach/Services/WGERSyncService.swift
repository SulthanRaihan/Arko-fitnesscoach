import Foundation
import FirebaseFirestore
import FirebaseAuth

// ════════════════════════════════════════════════════════════════════════════
// MARK: - WGER API Response Models
// ════════════════════════════════════════════════════════════════════════════

private struct WGERListResponse: Decodable {
    let count: Int
    let results: [WGERExerciseItem]
}

private struct WGERExerciseItem: Decodable {
    let id: Int
    let uuid: String
    let name: String?
    let description: String?
    let muscles: [WGERMuscle]
    let category: WGERCategory?
}

private struct WGERMuscle: Decodable {
    let id: Int
    let nameEn: String

    enum CodingKeys: String, CodingKey {
        case id
        case nameEn = "name_en"
    }
}

private struct WGERCategory: Decodable {
    let id: Int
    let name: String
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - WGERSyncService
// Fetches exercises from WGER REST API and caches them in Firestore under
// the global collection "exercises/{wger_id}" (shared across all users).
// On startup, checks if data is stale (>7 days) before re-fetching.
// ════════════════════════════════════════════════════════════════════════════

@MainActor
final class WGERSyncService: ObservableObject {
    static let shared = WGERSyncService()

    @Published private(set) var exercises: [WGERCachedExercise] = []
    @Published private(set) var isSyncing = false

    private let db = Firestore.firestore()
    private let wgerBase = "https://wger.de/api/v2"
    private let cacheCollection = "wger_exercises"
    private let metaDoc = "wger_exercises_meta"

    private init() {}

    // MARK: - Public entry point

    /// Load from Firestore cache; re-sync from WGER if stale or empty.
    func loadOrSync() async {
        let cached = await loadFromFirestore()
        let stale  = await isCacheStale()
        if cached.isEmpty || stale {
            await syncFromWGER()
        } else {
            exercises = cached
        }
    }

    // MARK: - Firestore cache read

    private func loadFromFirestore() async -> [WGERCachedExercise] {
        do {
            let snap = try await db.collection(cacheCollection).limit(to: 200).getDocuments()
            return snap.documents.compactMap { doc -> WGERCachedExercise? in
                let d = doc.data()
                guard let name = d["name"] as? String else { return nil }
                return WGERCachedExercise(
                    id: doc.documentID,
                    name: name,
                    description: d["description"] as? String ?? "",
                    category: d["category"] as? String ?? "",
                    muscles: d["muscles"] as? [String] ?? [],
                    imageURL: d["imageURL"] as? String
                )
            }
        } catch { return [] }
    }

    private func isCacheStale() async -> Bool {
        guard let meta = try? await db.collection("meta").document(metaDoc).getDocument(),
              meta.exists,
              let ts = meta.data()?["lastSync"] as? Timestamp
        else { return true }
        let days = Calendar.current.dateComponents([.day], from: ts.dateValue(), to: Date()).day ?? 99
        return days >= 7
    }

    // MARK: - WGER fetch + Firestore write

    func syncFromWGER() async {
        isSyncing = true
        defer { isSyncing = false }

        var fetched: [WGERCachedExercise] = []
        var offset = 0
        let limit  = 100

        // Fetch up to 300 English exercises
        while offset < 300 {
            let urlStr = "\(wgerBase)/exercise/?format=json&language=2&limit=\(limit)&offset=\(offset)"
            guard let url = URL(string: urlStr),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let list = try? JSONDecoder().decode(WGERListResponse.self, from: data)
            else { break }

            for item in list.results {
                guard let name = item.name, !name.isEmpty else { continue }
                let muscles = item.muscles.map { $0.nameEn }
                let ex = WGERCachedExercise(
                    id: String(item.id),
                    name: name,
                    description: item.description?.htmlStripped ?? "",
                    category: item.category?.name ?? "",
                    muscles: muscles,
                    imageURL: nil
                )
                fetched.append(ex)
            }

            if list.results.count < limit { break }
            offset += limit
        }

        guard !fetched.isEmpty else { return }

        // Write batch to Firestore
        let batch = db.batch()
        for ex in fetched {
            let ref = db.collection(cacheCollection).document(ex.id)
            batch.setData([
                "name":        ex.name,
                "description": ex.description,
                "category":    ex.category,
                "muscles":     ex.muscles,
                "imageURL":    ex.imageURL as Any,
            ], forDocument: ref)
        }
        // Update sync timestamp
        let metaRef = db.collection("meta").document(metaDoc)
        batch.setData(["lastSync": Timestamp(date: Date())], forDocument: metaRef)

        try? await batch.commit()
        exercises = fetched
    }

    // MARK: - Search helper

    func search(_ query: String) -> [WGERCachedExercise] {
        guard !query.isEmpty else { return exercises }
        let q = query.lowercased()
        return exercises.filter {
            $0.name.lowercased().contains(q) ||
            $0.category.lowercased().contains(q) ||
            $0.muscles.contains(where: { $0.lowercased().contains(q) })
        }
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - WGERCachedExercise (display model)
// ════════════════════════════════════════════════════════════════════════════

struct WGERCachedExercise: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let category: String
    let muscles: [String]
    let imageURL: String?
}

// MARK: - HTML strip helper

private extension String {
    var htmlStripped: String {
        guard let data = data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html,
                          .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil)
        else { return self }
        return attributed.string
    }
}
