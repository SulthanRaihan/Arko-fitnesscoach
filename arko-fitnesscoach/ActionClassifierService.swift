import Vision
import CoreML
import Foundation

// ════════════════════════════════════════════════════════════════════════════
// MARK: - ActionClassifierService
// Lapisan "Action Classifier" dari arsitektur hybrid:
//   Vision landmarks → (window pose) → Create ML Action Classifier → label
//
// Model OPSIONAL: kalau "ARKOActionClassifier.mlmodel" belum di-add ke project,
// service ini diam (nil) dan app jatuh ke rule-based murni. Begitu kamu rekam +
// train di Create ML lalu drop model-nya, klasifikasi langsung aktif.
//
// Window dibangun pakai VNHumanBodyPoseObservation.keypointsMultiArray() — format
// resmi yang diharapkan Create ML action classifier (shape [1,3,18] per frame,
// digabung jadi [window,3,18]).
// ════════════════════════════════════════════════════════════════════════════

struct ActionPrediction {
    let label: String
    let confidence: Float
    let probabilities: [String: Float]   // semua kelas + probabilitasnya
}

final class ActionClassifierService {
    static let shared = ActionClassifierService()

    private let model: MLModel?
    private let windowSize: Int
    private var buffer: [MLMultiArray] = []
    private let lock = NSLock()

    /// Riwayat probabilitas beberapa window terakhir → di-rata-rata (smoothing)
    /// supaya prediksi tidak flip-flop antar window.
    private var probHistory: [[String: Float]] = []
    private let smoothingWindows = 5

    /// Prediksi terakhir (sudah di-smooth).
    private(set) var latest: ActionPrediction?

    var isAvailable: Bool { model != nil }

    private init() {
        let config = MLModelConfiguration()
        let url = Bundle.main.url(forResource: "ARKOActionClassifier", withExtension: "mlmodelc")
               ?? Bundle.main.url(forResource: "ARKOActionClassifier", withExtension: "mlpackage")
        if let url, let m = try? MLModel(contentsOf: url, configuration: config) {
            model = m
            // Baca prediction window dari input description (default 60)
            if let desc = m.modelDescription.inputDescriptionsByName["poses"],
               let c = desc.multiArrayConstraint, c.shape.count == 3 {
                windowSize = c.shape[0].intValue
            } else {
                windowSize = 60
            }
            print("ActionClassifier ✅ loaded (window=\(windowSize))")
        } else {
            model = nil
            windowSize = 60
            print("ActionClassifier ⚠️ no model — using rule-based only")
        }
    }

    func reset() {
        lock.lock(); buffer.removeAll(); probHistory.removeAll(); latest = nil; lock.unlock()
    }

    /// Tambah 1 frame pose. Returns prediksi baru kalau window penuh.
    @discardableResult
    func addFrame(_ observation: VNHumanBodyPoseObservation) -> ActionPrediction? {
        guard let model else { return nil }
        guard let frame = try? observation.keypointsMultiArray() else { return nil }

        lock.lock()
        buffer.append(frame)
        if buffer.count > windowSize { buffer.removeFirst(buffer.count - windowSize) }
        let ready = buffer.count == windowSize
        let window = buffer
        lock.unlock()

        guard ready,
              let poses = try? MLMultiArray(concatenating: window, axis: 0, dataType: .float32)
        else { return latest }

        guard let provider = try? MLDictionaryFeatureProvider(dictionary: ["poses": poses]),
              let out = try? model.prediction(from: provider) else { return latest }

        // Output Create ML: "label" (String) + "labelProbabilities" ([String:Double])
        var probsF: [String: Float] = [:]
        if let probs = out.featureValue(for: "labelProbabilities")?.dictionaryValue as? [String: Double] {
            for (k, v) in probs { probsF[k] = Float(v) }
        }

        // Smoothing: rata-rata probabilitas N window terakhir → label dari hasil
        // rata-rata, bukan window tunggal (anti flip-flop antar fase gerakan).
        lock.lock()
        probHistory.append(probsF)
        if probHistory.count > smoothingWindows {
            probHistory.removeFirst(probHistory.count - smoothingWindows)
        }
        var avg: [String: Float] = [:]
        for dict in probHistory {
            for (k, v) in dict { avg[k, default: 0] += v }
        }
        let n = Float(probHistory.count)
        for k in avg.keys { avg[k]! /= n }

        let best = avg.max { $0.value < $1.value }
        let pred = ActionPrediction(
            label: best?.key ?? "unknown",
            confidence: best?.value ?? 0,
            probabilities: avg
        )
        latest = pred
        lock.unlock()
        return pred
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - FeedbackMapper
// Gabungkan label classifier (kalau ada) + status rule-based → pesan actionable.
// Konvensi label classifier: "<exercise>_<state>", mis. "squat_too_shallow".
// "*_correct" / "none" dianggap bagus.
// ════════════════════════════════════════════════════════════════════════════

enum FeedbackMapper {
    /// Map label classifier → FormStatus (untuk warna/ikon). nil = tidak yakin.
    static func status(forLabel label: String) -> FormStatus? {
        let l = label.lowercased()
        if l.contains("correct") || l == "none" || l == "other" { return .good }
        if l.contains("shallow") || l.contains("partial") || l.contains("high") { return .notDeep }
        if l.contains("knee")    { return .kneeAlignment }
        if l.contains("lean") || l.contains("back") || l.contains("round") { return .straighten }
        if l.contains("sag") || l.contains("pike") || l.contains("hip") { return .straighten }
        return nil
    }

    /// Judul yang ditampilkan = nama kelas dari model (lebih spesifik).
    static func title(forLabel label: String) -> String {
        switch label.lowercased() {
        case let l where l.contains("shallow"): return "Squat Too Shallow"
        case let l where l.contains("lean"):    return "Torso Leaning"
        case let l where l.contains("knee"):    return "Knees Caving In"
        case let l where l.contains("correct"): return "Good Form"
        default:
            // fallback: "squat_too_shallow" → "Squat Too Shallow"
            return label.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Saran actionable untuk tiap kelas.
    static func hint(forLabel label: String) -> String? {
        switch label.lowercased() {
        case let l where l.contains("shallow"): return "Lower until your thighs are parallel to the floor"
        case let l where l.contains("lean"):    return "Keep your chest up and back straight"
        case let l where l.contains("knee"):    return "Push your knees outward, in line with your toes"
        default: return nil
        }
    }

    /// Kalimat suara untuk koreksi.
    static func voice(forLabel label: String) -> String? {
        switch label.lowercased() {
        case let l where l.contains("shallow"): return "Too shallow. Go deeper."
        case let l where l.contains("lean"):    return "Torso leaning. Keep your chest up."
        case let l where l.contains("knee"):    return "Knees caving in. Push them out."
        default: return nil
        }
    }
}
