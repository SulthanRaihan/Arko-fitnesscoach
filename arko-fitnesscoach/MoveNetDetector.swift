import CoreML
import CoreImage
import AVFoundation

// ════════════════════════════════════════════════════════════════════════════
// MARK: - MoveNet Data Models
// MoveNet SinglePose Lightning — 17 keypoints
// Input:  [1, 192, 192, 3] int32 (RGB)
// Output: [1, 1, 17, 3]   float32 (y, x, confidence) — all normalized 0–1
// Coordinate origin: top-left (no Y-flip needed for display)
// ════════════════════════════════════════════════════════════════════════════

struct MoveNetKeypoint {
    let x: Float          // normalized 0–1 (left → right)
    let y: Float          // normalized 0–1 (top → bottom)
    let confidence: Float // 0–1
}

struct MoveNetPose {
    let keypoints: [MoveNetKeypoint]  // exactly 17, in enum order

    enum Joint: Int, CaseIterable {
        case nose = 0
        case leftEye = 1, rightEye = 2
        case leftEar = 3, rightEar = 4
        case leftShoulder = 5, rightShoulder = 6
        case leftElbow = 7, rightElbow = 8
        case leftWrist = 9, rightWrist = 10
        case leftHip = 11, rightHip = 12
        case leftKnee = 13, rightKnee = 14
        case leftAnkle = 15, rightAnkle = 16
    }

    /// Returns CGPoint (x,y) normalized 0–1, or nil if below confidence threshold.
    func point(for joint: Joint, minConfidence: Float = 0.25) -> CGPoint? {
        let kp = keypoints[joint.rawValue]
        guard kp.confidence >= minConfidence else { return nil }
        return CGPoint(x: CGFloat(kp.x), y: CGFloat(kp.y))
    }

    func avgConfidence(for joints: [Joint]) -> Float {
        let vals = joints.map { keypoints[$0.rawValue].confidence }
        return vals.reduce(0, +) / Float(max(vals.count, 1))
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - MoveNetDetector
// ════════════════════════════════════════════════════════════════════════════

final class MoveNetDetector {
    static let shared = MoveNetDetector()

    private let model: MLModel?
    private let targetSize = CGSize(width: 192, height: 192)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private init() {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine

        // Support both .mlpackage (iOS 15+) and compiled .mlmodelc
        let url = Bundle.main.url(forResource: "MoveNetLightning", withExtension: "mlpackage")
               ?? Bundle.main.url(forResource: "MoveNetLightning", withExtension: "mlmodelc")

        if let url = url, let m = try? MLModel(contentsOf: url, configuration: config) {
            model = m
            print("MoveNet ✅ loaded from \(url.lastPathComponent)")
        } else {
            model = nil
            print("MoveNet ⚠️ model not found — falling back to Apple Vision")
        }
    }

    // MARK: - Public

    func predict(pixelBuffer: CVPixelBuffer) -> MoveNetPose? {
        guard let model else { return nil }
        guard let resized  = resize(pixelBuffer),
              let inputArr = toMLArray(resized)   else { return nil }

        guard let fp = try? MLDictionaryFeatureProvider(
            dictionary: ["image": MLFeatureValue(multiArray: inputArr)]
        ) else { return nil }

        guard let result = try? model.prediction(from: fp) else { return nil }

        // Auto-find the first MLMultiArray output
        let outputArr: MLMultiArray? =
            result.featureValue(for: "output_0")?.multiArrayValue ??
            result.featureNames
                .lazy
                .compactMap { result.featureValue(for: $0)?.multiArrayValue }
                .first

        guard let arr = outputArr else { return nil }
        return parseOutput(arr)
    }

    // MARK: - Preprocessing

    private func resize(_ src: CVPixelBuffer) -> CVPixelBuffer? {
        let ci = CIImage(cvPixelBuffer: src)
        let sx = targetSize.width  / CGFloat(CVPixelBufferGetWidth(src))
        let sy = targetSize.height / CGFloat(CVPixelBufferGetHeight(src))
        let scaled = ci.transformed(by: CGAffineTransform(scaleX: sx, y: sy))

        var out: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault,
                            Int(targetSize.width), Int(targetSize.height),
                            kCVPixelFormatType_32BGRA, nil, &out)
        guard let out else { return nil }
        ciContext.render(scaled, to: out)
        return out
    }

    private func toMLArray(_ buf: CVPixelBuffer) -> MLMultiArray? {
        let w = Int(targetSize.width)
        let h = Int(targetSize.height)

        guard let arr = try? MLMultiArray(
            shape: [1, h as NSNumber, w as NSNumber, 3],
            dataType: .int32) else { return nil }

        CVPixelBufferLockBaseAddress(buf, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buf, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(buf) else { return nil }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let bpr   = CVPixelBufferGetBytesPerRow(buf)
        let dst   = arr.dataPointer.assumingMemoryBound(to: Int32.self)

        for row in 0..<h {
            for col in 0..<w {
                let px  = row * bpr   + col * 4  // BGRA source
                let out = row * w * 3 + col * 3  // RGB target
                dst[out]     = Int32(bytes[px + 2]) // R
                dst[out + 1] = Int32(bytes[px + 1]) // G
                dst[out + 2] = Int32(bytes[px])     // B
            }
        }
        return arr
    }

    // MARK: - Parse output [1, 1, 17, 3] → MoveNetPose

    private func parseOutput(_ arr: MLMultiArray) -> MoveNetPose? {
        guard arr.count >= 51 else { return nil }  // 17 × 3

        // Float16 or Float32 — handle both
        let keypoints: [MoveNetKeypoint]
        if arr.dataType == .float32 {
            let ptr = arr.dataPointer.assumingMemoryBound(to: Float.self)
            keypoints = (0..<17).map { i in
                MoveNetKeypoint(x: ptr[i*3+1], y: ptr[i*3], confidence: ptr[i*3+2])
            }
        } else {
            // Fallback: use subscript (slower but safe)
            keypoints = (0..<17).map { i -> MoveNetKeypoint in
                let kx = arr[i*3+1].floatValue
                let ky = arr[i*3].floatValue
                let kc = arr[i*3+2].floatValue
                return MoveNetKeypoint(x: kx, y: ky, confidence: kc)
            }
        }
        return MoveNetPose(keypoints: keypoints)
    }
}
