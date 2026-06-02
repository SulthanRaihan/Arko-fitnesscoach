import SwiftUI
import UIKit
import ImageIO

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Exercise GIF (ExerciseDB)
// The ExerciseDB image endpoint needs RapidAPI headers, so we download the GIF
// data ourselves (with headers), decode into an animated UIImage via ImageIO,
// and display it. Falls back to an SF Symbol icon on failure.
// ════════════════════════════════════════════════════════════════════════════

private let exerciseGIFCache = NSCache<NSString, UIImage>()

/// Core view: given a cache key + an async request provider, show animated GIF.
struct GIFCoreView: View {
    let cacheKey: String
    let fallbackIcon: String
    let requestProvider: () async -> URLRequest?

    @State private var image: UIImage?
    @State private var failed = false
    @State private var loaded = false

    var body: some View {
        ZStack {
            if let image {
                GIFImageView(image: image)
            } else if failed {
                Image(systemName: fallbackIcon)
                    .font(.system(size: 36))
                    .foregroundStyle(Color.arkoLime.opacity(0.5))
            } else {
                ProgressView().tint(Color.arkoLime)
            }
        }
        .task {
            guard !loaded else { return }
            loaded = true
            await load()
        }
    }

    private func load() async {
        let key = cacheKey as NSString
        if let cached = exerciseGIFCache.object(forKey: key) { image = cached; return }
        guard let req = await requestProvider(),
              let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let decoded = GIFCoreView.animatedImage(from: data)
        else { failed = true; return }
        exerciseGIFCache.setObject(decoded, forKey: key)
        image = decoded
    }

    static func animatedImage(from data: Data) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }
        let count = CGImageSourceGetCount(src)
        if count <= 1 { return UIImage(data: data) }
        var frames: [UIImage] = []
        var duration: Double = 0
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            frames.append(UIImage(cgImage: cg))
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                     ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            duration += max(delay, 0.02)
        }
        return UIImage.animatedImage(with: frames, duration: duration)
    }
}

/// GIF for one of our local Exercises (looked up by name).
struct ExerciseGIFView: View {
    let exercise: Exercise
    var resolution: Int = 360

    var body: some View {
        GIFCoreView(cacheKey: "name:\(exercise.name.lowercased())",
                    fallbackIcon: exercise.icon) {
            await ExerciseDBService.shared.gifRequest(for: exercise.name, resolution: resolution)
        }
    }
}

/// GIF for an ExerciseDB result (known id) — used in Browse by Muscle.
struct ExerciseDBGIFView: View {
    let id: String
    var icon: String = "figure.run"
    var resolution: Int = 360

    var body: some View {
        GIFCoreView(cacheKey: "id:\(id)", fallbackIcon: icon) {
            await ExerciseDBService.shared.gifRequest(forId: id, resolution: resolution)
        }
    }
}

// MARK: - UIImageView bridge (animates UIImage.animatedImage)

private struct GIFImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let v = UIImageView()
        v.contentMode = .scaleAspectFit
        v.clipsToBounds = true
        v.setContentHuggingPriority(.defaultLow, for: .vertical)
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return v
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        uiView.image = image
    }
}
