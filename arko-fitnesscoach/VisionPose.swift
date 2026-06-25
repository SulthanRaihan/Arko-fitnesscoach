import Vision
import CoreGraphics

// ════════════════════════════════════════════════════════════════════════════
// MARK: - BodyPose (Apple Vision body landmarks)
// Mirror dari API MoveNetPose lama supaya RepCounter/PoseOverlay/ExerciseConfig
// hampir tidak berubah. Sumber: VNDetectHumanBodyPoseRequest.
// Koordinat di-flip ke origin kiri-atas (sama seperti layar) agar overlay & sudut
// konsisten.
// ════════════════════════════════════════════════════════════════════════════

struct BodyPose {
    enum Joint: CaseIterable {
        case nose
        case leftShoulder, rightShoulder
        case leftElbow, rightElbow
        case leftWrist, rightWrist
        case leftHip, rightHip
        case leftKnee, rightKnee
        case leftAnkle, rightAnkle

        var vn: VNHumanBodyPoseObservation.JointName {
            switch self {
            case .nose:          return .nose
            case .leftShoulder:  return .leftShoulder
            case .rightShoulder: return .rightShoulder
            case .leftElbow:     return .leftElbow
            case .rightElbow:    return .rightElbow
            case .leftWrist:     return .leftWrist
            case .rightWrist:    return .rightWrist
            case .leftHip:       return .leftHip
            case .rightHip:      return .rightHip
            case .leftKnee:      return .leftKnee
            case .rightKnee:     return .rightKnee
            case .leftAnkle:     return .leftAnkle
            case .rightAnkle:    return .rightAnkle
            }
        }
    }

    private var points: [Joint: CGPoint] = [:]
    private var confs:  [Joint: Float] = [:]

    init() {}

    init(observation: VNHumanBodyPoseObservation, minConfidence: Float = 0.1) {
        for j in Joint.allCases {
            guard let p = try? observation.recognizedPoint(j.vn),
                  p.confidence >= minConfidence else { continue }
            // Vision origin = bottom-left → flip Y to top-left
            points[j] = CGPoint(x: p.location.x, y: 1 - p.location.y)
            confs[j]  = p.confidence
        }
    }

    func point(for j: Joint, minConfidence: Float = 0.2) -> CGPoint? {
        guard let c = confs[j], c >= minConfidence else { return nil }
        return points[j]
    }

    func confidence(for j: Joint) -> Float { confs[j] ?? 0 }

    func avgConfidence(for joints: [Joint]) -> Float {
        let vals = joints.map { confs[$0] ?? 0 }
        return vals.reduce(0, +) / Float(max(vals.count, 1))
    }

    var hasBody: Bool { confs.count >= 6 }
}
