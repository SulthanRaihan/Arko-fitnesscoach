import Foundation

// ════════════════════════════════════════════════════════════════════════════
// MARK: - WGER API Models
// ════════════════════════════════════════════════════════════════════════════

private struct WGERSearchResponse: Decodable {
    let suggestions: [WGERSuggestion]
}

private struct WGERSuggestion: Decodable {
    let value: String
    let data: WGERSuggestionData
}

private struct WGERSuggestionData: Decodable {
    let id: Int
    let baseId: Int
    let image: String?
    let imageThumbnail: String?

    enum CodingKeys: String, CodingKey {
        case id
        case baseId = "base_id"
        case image
        case imageThumbnail = "image_thumbnail"
    }
}

private struct WGERImageListResponse: Decodable {
    let results: [WGERExerciseImage]
}

private struct WGERExerciseImage: Decodable {
    let image: String
    let isMain: Bool

    enum CodingKeys: String, CodingKey {
        case image
        case isMain = "is_main"
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - WGERService (actor for thread-safe caching)
// ════════════════════════════════════════════════════════════════════════════

actor WGERService {
    static let shared = WGERService()

    // nil value means "searched but found nothing" (prevents repeated requests)
    private var imageCache: [String: URL?] = [:]

    private let baseURL = "https://wger.de"
    private let session = URLSession.shared

    private init() {}

    /// Returns the main image URL for an exercise name, or nil if not found.
    /// Results are cached in-memory for the app session.
    func imageURL(for exerciseName: String) async -> URL? {
        let key = exerciseName.lowercased()
        if let cached = imageCache[key] { return cached }

        let url = await resolveImageURL(name: exerciseName)
        imageCache[key] = url
        return url
    }

    // MARK: - Private resolution

    private func resolveImageURL(name: String) async -> URL? {
        // Try several search terms — full name first, then individual words.
        // Many WGER entries are named differently (e.g. "Fly" vs "Chest Fly").
        let words = name.split(separator: " ").map(String.init)
        var terms = [name]
        if let first = words.first, first.lowercased() != name.lowercased() { terms.append(first) }
        if let last = words.last, last != words.first { terms.append(last) }

        for term in terms {
            if let url = await firstImage(forTerm: term) { return url }
        }
        return nil
    }

    /// Search one term, scan ALL suggestions, return the first image found.
    private func firstImage(forTerm term: String) async -> URL? {
        guard let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "\(baseURL)/api/v2/exercise/search/?term=\(encoded)&language=english&format=json")
        else { return nil }

        guard let (data, _) = try? await session.data(from: searchURL),
              let result = try? JSONDecoder().decode(WGERSearchResponse.self, from: data)
        else { return nil }

        for suggestion in result.suggestions {
            // Inline thumbnail?
            if let thumb = suggestion.data.imageThumbnail ?? suggestion.data.image {
                return URL(string: thumb.hasPrefix("http") ? thumb : "\(baseURL)\(thumb)")
            }
            // Otherwise look up images by base_id
            if let url = await imageByBaseId(suggestion.data.baseId) {
                return url
            }
        }
        return nil
    }

    private func imageByBaseId(_ baseId: Int) async -> URL? {
        guard let url = URL(string: "\(baseURL)/api/v2/exerciseimage/?format=json&exercise_base=\(baseId)"),
              let (data, _) = try? await session.data(from: url),
              let list = try? JSONDecoder().decode(WGERImageListResponse.self, from: data)
        else { return nil }
        let chosen = list.results.first(where: { $0.isMain }) ?? list.results.first
        guard let path = chosen?.image else { return nil }
        return URL(string: path.hasPrefix("http") ? path : "\(baseURL)\(path)")
    }
}
