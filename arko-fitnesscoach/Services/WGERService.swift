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
        // Step 1: search for the exercise to get base_id
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "\(baseURL)/api/v2/exercise/search/?term=\(encoded)&language=english&format=json")
        else { return nil }

        guard let (data, _) = try? await session.data(from: searchURL),
              let searchResult = try? JSONDecoder().decode(WGERSearchResponse.self, from: data),
              let first = searchResult.suggestions.first
        else { return nil }

        // Use thumbnail from search result if available
        if let thumb = first.data.imageThumbnail ?? first.data.image,
           let url = URL(string: thumb.hasPrefix("http") ? thumb : "\(baseURL)\(thumb)") {
            return url
        }

        // Step 2: fetch images by base_id
        let baseId = first.data.baseId
        guard let imgListURL = URL(string: "\(baseURL)/api/v2/exerciseimage/?format=json&exercise_base=\(baseId)") else { return nil }

        guard let (imgData, _) = try? await session.data(from: imgListURL),
              let imgList = try? JSONDecoder().decode(WGERImageListResponse.self, from: imgData)
        else { return nil }

        // Prefer main image, fall back to first available
        let chosen = imgList.results.first(where: { $0.isMain }) ?? imgList.results.first
        guard let imgPath = chosen?.image else { return nil }

        let fullPath = imgPath.hasPrefix("http") ? imgPath : "\(baseURL)\(imgPath)"
        return URL(string: fullPath)
    }
}
