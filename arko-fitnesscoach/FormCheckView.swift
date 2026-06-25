import SwiftUI
import AVFoundation
import Vision

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Exercise Configuration (port dari Good-GYM exercises.json)
// ════════════════════════════════════════════════════════════════════════════

struct ExerciseConfig {
    enum Orientation { case vertical, horizontal }

    let name: String
    let downAngle: Double
    let upAngle: Double
    let jointA: BodyPose.Joint
    let jointB: BodyPose.Joint  // center (vertex of angle)
    let jointC: BodyPose.Joint
    let orientation: Orientation   // expected body posture for a valid rep

    static let all: [String: ExerciseConfig] = [
        "Squat": ExerciseConfig(
            name: "Squat",
            downAngle: 110, upAngle: 160,
            jointA: .rightHip, jointB: .rightKnee, jointC: .rightAnkle,
            orientation: .vertical
        ),
        "Push-up": ExerciseConfig(
            name: "Push-up",
            downAngle: 90, upAngle: 160,
            jointA: .rightShoulder, jointB: .rightElbow, jointC: .rightWrist,
            orientation: .horizontal
        ),
        "Deadlift": ExerciseConfig(
            name: "Deadlift",
            downAngle: 110, upAngle: 170,
            jointA: .rightShoulder, jointB: .rightHip, jointC: .rightKnee,
            orientation: .vertical
        ),
        "Lunge": ExerciseConfig(
            name: "Lunge",
            downAngle: 100, upAngle: 160,
            jointA: .rightHip, jointB: .rightKnee, jointC: .rightAnkle,
            orientation: .vertical
        ),
        "Plank": ExerciseConfig(
            name: "Plank",
            downAngle: 165, upAngle: 175,
            jointA: .rightShoulder, jointB: .rightHip, jointC: .rightAnkle,
            orientation: .horizontal
        ),
    ]
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Rep Counter + Form Analyzer (Lesson 10)
// ════════════════════════════════════════════════════════════════════════════

/// Status form feedback — sesuai MLAgent FORM_STATUS_LABELS di backend
enum FormStatus: String {
    case good           = "good"
    case notDeep        = "not_deep"
    case kneeAlignment  = "knee_alignment"
    case notVisible     = "not_visible"
    case lowConfidence  = "low_confidence"
    case wrongPose      = "wrong_pose"
    case straighten     = "straighten"

    var label: String {
        switch self {
        case .good:          return "Good form"
        case .notDeep:       return "Go deeper"
        case .kneeAlignment: return "Knees out"
        case .notVisible:    return "Step into frame"
        case .lowConfidence: return "Improve lighting"
        case .wrongPose:     return "Get into position"
        case .straighten:    return "Keep body straight"
        }
    }

    var color: String {
        switch self {
        case .good:          return "green"
        case .notDeep:       return "orange"
        case .kneeAlignment: return "orange"
        case .notVisible:    return "red"
        case .lowConfidence: return "red"
        case .wrongPose:     return "orange"
        case .straighten:    return "orange"
        }
    }
}

/// Satu event form check yang dicatat selama sesi
struct FormEvent {
    let status: FormStatus
    let timestamp: TimeInterval
}

final class RepCounter: ObservableObject {
    @Published var count: Int = 0
    @Published var currentAngle: Double = 0
    @Published var stage: String = "—"   // "up" / "down" / "—"
    /// Live status — HANYA untuk masalah posisi (notVisible / wrongPose).
    /// Kualitas gerakan dinilai per-rep lewat `lastVerdict`.
    @Published var formStatus: FormStatus = .good
    @Published var formEvents: [FormEvent] = []

    /// Verdict rep terakhir (dinilai sekali saat rep selesai, bukan per-frame).
    @Published var lastVerdict: FormStatus?
    /// Bertambah tiap rep selesai — pemicu UI/voice walau verdict-nya sama.
    @Published var verdictSeq: Int = 0

    // Plank (time-based hold)
    @Published var holdSeconds: Int = 0
    private var holdAccumulated: TimeInterval = 0
    private var holdResumeAt: Date?

    private var lastCountTime: TimeInterval = 0
    private let minRepInterval: TimeInterval = 0.5
    private var sessionStart = Date()

    // Akumulator sinyal selama 1 rep (dinilai di finishRep)
    private var repMinAngle: Double = 999        // sudut lutut terdalam
    private var repDeepFrames: Int = 0           // frame dgn pinggul ≈/di bawah lutut (anti-noise)
    private var repHipTracked = false            // apakah hip+knee terlacak selama rep
    private var repMaxLeanDeg: Double = 0        // kemiringan torso maksimal di bottom region
    private var repLeanProbSum: Double = 0       // voting model: prob "lean" sepanjang rep
    private var repLeanProbN: Int = 0
    private var repKneeCaving = false
    private var downStreak = 0                   // frame beruntun di bawah threshold (debounce)

    // Debounce supaya teguran posisi tidak nyasar sesaat
    private var badOrientationSince: Date?
    private var notVisibleSince: Date?

    func reset() {
        count = 0
        stage = "—"
        currentAngle = 0
        formStatus = .good
        formEvents = []
        lastVerdict = nil
        verdictSeq = 0
        holdSeconds = 0
        holdAccumulated = 0
        holdResumeAt = nil
        badOrientationSince = nil
        notVisibleSince = nil
        resetRepAccumulators()
        sessionStart = Date()
    }

    private func resetRepAccumulators() {
        repMinAngle = 999
        repDeepFrames = 0
        repHipTracked = false
        repMaxLeanDeg = 0
        repLeanProbSum = 0
        repLeanProbN = 0
        repKneeCaving = false
        downStreak = 0
    }

    /// Update per-frame: kumpulkan sinyal DIAM-DIAM selama rep, lalu beri SATU
    /// verdict saat rep selesai (finishRep). Tidak ada teguran di tengah gerakan.
    func update(pose: BodyPose, exercise: String, action: ActionPrediction? = nil) {
        guard let config = ExerciseConfig.all[exercise] else { return }

        // Plank = isometric hold → timer + feedback postur, bukan reps.
        if config.name == "Plank" {
            updatePlank(pose: pose, config: config)
            return
        }

        // GATE 1 — orientasi: HANYA dicek saat TIDAK sedang di tengah rep
        // (saat squat dalam, badan wajar condong → jangan dituduh salah posisi).
        // Harus salah terus ≥1 detik baru ditegur (anti teguran nyasar).
        if stage != "down" {
            if orientationMatches(pose: pose, expected: config.orientation) {
                badOrientationSince = nil
            } else {
                if badOrientationSince == nil { badOrientationSince = Date() }
                if Date().timeIntervalSince(badOrientationSince!) > 1.0 {
                    setLive(.wrongPose)
                    return
                }
            }
        } else {
            badOrientationSince = nil
        }

        // GATE 2 — visibility, debounced 0.8 detik.
        let angleConf = pose.avgConfidence(for: [config.jointA, config.jointB, config.jointC])
        guard angleConf >= 0.3,
              let a = pose.point(for: config.jointA),
              let b = pose.point(for: config.jointB),
              let c = pose.point(for: config.jointC)
        else {
            if notVisibleSince == nil { notVisibleSince = Date() }
            if Date().timeIntervalSince(notVisibleSince!) > 0.8 { setLive(.notVisible) }
            return
        }
        notVisibleSince = nil
        setLive(.good)   // posisi beres → bersihkan warning

        let angle = calculateAngle(a: a, b: b, c: c)
        currentAngle = angle

        // ── Kumpulkan sinyal selama rep (tanpa menegur) ──────────────────────
        repMinAngle = min(repMinAngle, angle)

        if exercise == "Squat" {
            // Depth klasik side-view: pinggul mencapai/melewati level lutut.
            // Toleransi dinormalisasi panjang paha (scale-aware: jauh/dekat kamera
            // sama ketatnya), dan harus BERTAHAN beberapa frame (anti noise 1-frame).
            if let hip  = pose.point(for: .rightHip)  ?? pose.point(for: .leftHip),
               let knee = pose.point(for: .rightKnee) ?? pose.point(for: .leftKnee) {
                repHipTracked = true
                let thigh = Double(hypot(hip.x - knee.x, hip.y - knee.y))
                let tol = thigh * 0.15   // pinggul max 15% panjang paha di atas lutut ≈ paralel
                if Double(hip.y - knee.y) >= -tol, angle < config.downAngle + 15 {
                    repDeepFrames += 1
                }
            }
            // Torso lean diukur konsisten hanya di bottom region (condong saat
            // turun itu wajar; yang dinilai adalah kemiringan di titik bawah).
            if angle < config.downAngle + 20, let lean = torsoLeanDegrees(pose: pose) {
                repMaxLeanDeg = max(repMaxLeanDeg, lean)
            }
            // Knee caving hanya relevan di posisi bawah.
            if angle < config.downAngle + 10, isKneeCaving(pose: pose) {
                repKneeCaving = true
            }
            // Voting model: kumpulkan probabilitas "lean" sepanjang rep.
            if let action {
                let leanProb = action.probabilities
                    .first { $0.key.lowercased().contains("lean") }?.value ?? 0
                repLeanProbSum += Double(leanProb)
                repLeanProbN += 1
            }
        }

        // ── State machine rep ────────────────────────────────────────────────
        let now = Date().timeIntervalSince1970
        if angle > config.upAngle {
            downStreak = 0
            if stage == "down" && (now - lastCountTime) > minRepInterval {
                finishRep(config: config, exercise: exercise)
                lastCountTime = now
            }
            stage = "up"
        } else if angle < config.downAngle {
            // Harus 2 frame beruntun di bawah threshold baru dianggap fase "down"
            // (1 frame noise tidak memicu rep palsu).
            downStreak += 1
            if downStreak >= 2 { stage = "down" }
        }
    }

    /// Verdict SATU kali per rep — arbitrase geometri + voting model.
    private func finishRep(config: ExerciseConfig, exercise: String) {
        count += 1

        var verdict: FormStatus = .good
        if exercise == "Squat" {
            let avgLeanProb = repLeanProbN > 0 ? repLeanProbSum / Double(repLeanProbN) : 0

            // 1) DEPTH — geometri pegang keputusan penuh.
            //    Kalau hip+knee terlacak: pinggul harus bertahan ≥3 frame di level
            //    lutut (scale-aware) — bukan OR longgar yang bisa kecolongan noise.
            //    Backup sudut HANYA kalau hip tidak terlacak, dan lebih ketat (≤90°).
            let deepEnough: Bool
            if repHipTracked {
                deepEnough = repDeepFrames >= 3
            } else {
                deepEnough = repMinAngle <= config.downAngle - 20
            }

            // 2) TORSO LEAN — geometri + model voting (dua sumber):
            //    >55° = jelas condong (geometri saja cukup);
            //    40–55° + model rata-rata yakin lean → condong.
            let leanGeometry = repMaxLeanDeg > 55
            let leanHybrid   = repMaxLeanDeg > 40 && avgLeanProb > 0.5

            if !deepEnough              { verdict = .notDeep }
            else if leanGeometry || leanHybrid { verdict = .straighten }
            else if repKneeCaving       { verdict = .kneeAlignment }
        }

        formEvents.append(FormEvent(
            status: verdict,
            timestamp: Date().timeIntervalSince(sessionStart)
        ))
        lastVerdict = verdict
        verdictSeq += 1
        resetRepAccumulators()
    }

    /// Kemiringan torso dari vertikal (0° = tegak, 90° = horizontal).
    private func torsoLeanDegrees(pose: BodyPose) -> Double? {
        guard let ls = pose.point(for: .leftShoulder),
              let rs = pose.point(for: .rightShoulder),
              let lh = pose.point(for: .leftHip),
              let rh = pose.point(for: .rightHip) else { return nil }
        let sh  = CGPoint(x: (ls.x + rs.x) / 2, y: (ls.y + rs.y) / 2)
        let hip = CGPoint(x: (lh.x + rh.x) / 2, y: (lh.y + rh.y) / 2)
        let dx = Double(abs(sh.x - hip.x))
        let dy = Double(abs(sh.y - hip.y))
        return atan2(dx, dy) * 180.0 / Double.pi
    }

    private func isKneeCaving(pose: BodyPose) -> Bool {
        guard let lK = pose.point(for: .leftKnee),  let rK = pose.point(for: .rightKnee),
              let lA = pose.point(for: .leftAnkle), let rA = pose.point(for: .rightAnkle)
        else { return false }
        return abs(lK.x - rK.x) < abs(lA.x - rA.x) * 0.55
    }

    private func setLive(_ s: FormStatus) {
        if formStatus != s { formStatus = s }
    }

    /// Cek orientasi torso (bahu→pinggul) cocok dengan yang diharapkan.
    /// Hanya BLOKIR kalau jelas berlawanan, supaya rep sah tidak ikut terblokir.
    private func orientationMatches(pose: BodyPose, expected: ExerciseConfig.Orientation) -> Bool {
        guard let ls = pose.point(for: .leftShoulder),
              let rs = pose.point(for: .rightShoulder),
              let lh = pose.point(for: .leftHip),
              let rh = pose.point(for: .rightHip)
        else { return true }   // tidak cukup data → jangan blokir

        let shoulder = CGPoint(x: (ls.x + rs.x) / 2, y: (ls.y + rs.y) / 2)
        let hip      = CGPoint(x: (lh.x + rh.x) / 2, y: (lh.y + rh.y) / 2)
        let dx = abs(shoulder.x - hip.x)
        let dy = abs(shoulder.y - hip.y)

        switch expected {
        case .vertical:   return dy >= dx * 0.8   // blokir kalau jelas horizontal
        case .horizontal: return dx >= dy * 0.8   // blokir kalau jelas vertikal
        }
    }

    // MARK: Plank (hold timer + posture feedback)

    private func updatePlank(pose: BodyPose, config: ExerciseConfig) {
        // Harus posisi horizontal (kalau squat/berdiri → tidak valid, timer pause)
        guard orientationMatches(pose: pose, expected: .horizontal) else {
            pauseHold(); formStatus = .wrongPose; return
        }
        let conf = pose.avgConfidence(for: [config.jointA, config.jointB, config.jointC])
        guard conf >= 0.35,
              let a = pose.point(for: config.jointA),   // shoulder
              let b = pose.point(for: config.jointB),   // hip
              let c = pose.point(for: config.jointC)    // ankle
        else { pauseHold(); formStatus = .notVisible; return }

        // Sudut bahu-pinggul-pergelangan kaki: ~180° = badan lurus
        let angle = calculateAngle(a: a, b: b, c: c)
        currentAngle = angle

        // Badan lurus (160–185) → hold valid. Di luar itu → pinggul turun/naik.
        if angle >= 160 {
            formStatus = .good
            validHold()
        } else {
            formStatus = .straighten      // pinggul melorot / naik
            validHold()                   // tetap dihitung waktunya, tapi diberi feedback
        }
        // Catat event tiap ~2 detik untuk report
        if holdSeconds > 0 && holdSeconds % 2 == 0 {
            formEvents.append(FormEvent(status: formStatus,
                                        timestamp: Date().timeIntervalSince(sessionStart)))
        }
    }

    private func validHold() {
        if holdResumeAt == nil { holdResumeAt = Date() }
        let live = Date().timeIntervalSince(holdResumeAt!)
        holdSeconds = Int(holdAccumulated + live)
    }

    private func pauseHold() {
        if let r = holdResumeAt {
            holdAccumulated += Date().timeIntervalSince(r)
            holdResumeAt = nil
        }
    }

    /// Extract keypoints for UIAgent — Vision version
    static func extractKeypoints(from pose: BodyPose) -> [[String: Double]] {
        let joints: [(String, BodyPose.Joint)] = [
            ("left_shoulder",  .leftShoulder),  ("right_shoulder", .rightShoulder),
            ("left_elbow",     .leftElbow),     ("right_elbow",    .rightElbow),
            ("left_wrist",     .leftWrist),     ("right_wrist",    .rightWrist),
            ("left_hip",       .leftHip),       ("right_hip",      .rightHip),
            ("left_knee",      .leftKnee),      ("right_knee",     .rightKnee),
            ("left_ankle",     .leftAnkle),     ("right_ankle",    .rightAnkle),
        ]
        return joints.enumerated().compactMap { idx, pair in
            guard let p = pose.point(for: pair.1) else { return nil }
            return [
                "joint_index": Double(idx),
                "x": Double(p.x), "y": Double(p.y),
                "confidence": Double(pose.confidence(for: pair.1))
            ]
        }
    }

    /// Hitung sudut di titik B yang dibentuk oleh A-B-C (dalam derajat)
    private func calculateAngle(a: CGPoint, b: CGPoint, c: CGPoint) -> Double {
        let ba = CGVector(dx: a.x - b.x, dy: a.y - b.y)
        let bc = CGVector(dx: c.x - b.x, dy: c.y - b.y)

        let dot = ba.dx * bc.dx + ba.dy * bc.dy
        let magBA = sqrt(ba.dx * ba.dx + ba.dy * ba.dy)
        let magBC = sqrt(bc.dx * bc.dx + bc.dy * bc.dy)

        guard magBA > 0, magBC > 0 else { return 0 }

        let cosAngle = max(-1, min(1, dot / (magBA * magBC)))
        return Double(acos(cosAngle)) * 180.0 / Double.pi
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Camera Manager (AVFoundation + Vision Pose Detection)
// ════════════════════════════════════════════════════════════════════════════

final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "arko.camera.queue", qos: .userInteractive)
    private var currentCamera: AVCaptureDevice.Position = .front

    // Apple Vision body pose + optional Action Classifier
    @Published var bodyPose: BodyPose?
    @Published var actionLabel: String?
    @Published var actionConfidence: Float = 0
    @Published var actionProbs: [String: Float] = [:]
    @Published var isAuthorized = false
    @Published var errorMessage: String?

    private let poseRequest = VNDetectHumanBodyPoseRequest()

    override init() {
        super.init()
    }

    // MARK: Permission

    func checkPermission() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            await MainActor.run { isAuthorized = true }
            setupSession()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            await MainActor.run { isAuthorized = granted }
            if granted { setupSession() }
        case .denied, .restricted:
            await MainActor.run {
                isAuthorized = false
                errorMessage = "Camera access denied. Enable in Settings."
            }
        @unknown default:
            break
        }
    }

    // MARK: Session Setup

    private func setupSession() {
        videoQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            // Input
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                       for: .video,
                                                       position: self.currentCamera),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)

            // Output
            self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }

            // Orientation
            if let connection = self.videoOutput.connection(with: .video) {
                connection.videoOrientation = .portrait
                connection.isVideoMirrored = (self.currentCamera == .front)
            }

            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }

    func switchCamera() {
        currentCamera = (currentCamera == .front) ? .back : .front
        videoQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.stopRunning()
            self.session.inputs.forEach { self.session.removeInput($0) }
            self.session.outputs.forEach { self.session.removeOutput($0) }
            self.setupSession()
        }
    }

    func stop() {
        videoQueue.async { [weak self] in self?.session.stopRunning() }
    }

    // MARK: Vision Pose Detection + Action Classifier

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try? handler.perform([poseRequest])
        guard let observation = poseRequest.results?.first else { return }

        let pose = BodyPose(observation: observation)
        // Feed window to the (optional) Create ML action classifier
        let prediction = ActionClassifierService.shared.addFrame(observation)

        DispatchQueue.main.async { [weak self] in
            self?.bodyPose = pose
            if let p = prediction {
                self?.actionLabel = p.label
                self?.actionConfidence = p.confidence
                self?.actionProbs = p.probabilities
            }
        }
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Camera Preview (UIKit bridge)
// ════════════════════════════════════════════════════════════════════════════

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Pose Skeleton Overlay
// ════════════════════════════════════════════════════════════════════════════

struct PoseOverlay: View {
    let pose: BodyPose?

    // Body bones only — NO face connections (eyes/ears jitter & look messy)
    private let connections: [(BodyPose.Joint, BodyPose.Joint)] = [
        (.leftShoulder, .leftElbow),   (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftHip),     (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        (.leftHip, .leftKnee),         (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee),       (.rightKnee, .rightAnkle),
    ]

    // Body joint dots only — head drawn separately as a circle
    private let joints: [BodyPose.Joint] = [
        .leftShoulder, .rightShoulder,
        .leftElbow, .rightElbow, .leftWrist, .rightWrist,
        .leftHip, .rightHip, .leftKnee, .rightKnee,
        .leftAnkle, .rightAnkle,
    ]

    var body: some View {
        GeometryReader { _ in
            Canvas { ctx, size in
                guard let pose else { return }

                // Neck + head: draw a clean circle at the nose, with a short
                // neck line down to the shoulder midpoint.
                if let nose = screenPt(pose.point(for: .nose), size: size) {
                    let midShoulder = midpoint(pose.point(for: .leftShoulder),
                                               pose.point(for: .rightShoulder), size: size)
                    if let neck = midShoulder {
                        var neckPath = Path()
                        neckPath.move(to: nose); neckPath.addLine(to: neck)
                        ctx.stroke(neckPath, with: .color(.orange),
                                   style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    }
                    let headR: CGFloat = 16
                    let headRect = CGRect(x: nose.x - headR, y: nose.y - headR,
                                          width: headR * 2, height: headR * 2)
                    ctx.fill(Path(ellipseIn: headRect), with: .color(.orange.opacity(0.25)))
                    ctx.stroke(Path(ellipseIn: headRect), with: .color(.orange), lineWidth: 3)
                }

                // Bones
                for (a, b) in connections {
                    if let p1 = screenPt(pose.point(for: a), size: size),
                       let p2 = screenPt(pose.point(for: b), size: size) {
                        var path = Path()
                        path.move(to: p1); path.addLine(to: p2)
                        ctx.stroke(path, with: .color(.orange),
                                   style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    }
                }

                // Joint dots
                for joint in joints {
                    if let p = screenPt(pose.point(for: joint), size: size) {
                        let r = CGRect(x: p.x-5, y: p.y-5, width: 10, height: 10)
                        ctx.fill(Path(ellipseIn: r), with: .color(.white))
                        ctx.stroke(Path(ellipseIn: r), with: .color(.orange), lineWidth: 2)
                    }
                }
            }
        }
    }

    private func midpoint(_ p1: CGPoint?, _ p2: CGPoint?, size: CGSize) -> CGPoint? {
        guard let a = screenPt(p1, size: size), let b = screenPt(p2, size: size) else { return nil }
        return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    // MoveNet origin = top-left, same as screen → no Y-flip needed
    private func screenPt(_ pt: CGPoint?, size: CGSize) -> CGPoint? {
        guard let pt else { return nil }
        return CGPoint(x: pt.x * size.width, y: pt.y * size.height)
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - FormCheckView
// ════════════════════════════════════════════════════════════════════════════

struct FormCheckView: View {
    // presetExercise + onFinish → focused single-exercise camera (dari setup flow / workout)
    var presetExercise: String? = nil
    var repTarget: Int? = nil          // target reps (atau detik untuk Plank)
    var onFinish: ((Int) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraManager()
    @StateObject private var counter = RepCounter()
    @StateObject private var voice = VoiceCoach()
    @State private var selectedExercise = "Squat"
    @State private var lastPose: BodyPose?
    @State private var formFeedback: String?
    @State private var isLoadingFeedback = false
    @State private var report: FormReportResponse?
    @State private var showReport = false
    @State private var isLoadingReport = false
    @State private var targetReached = false

    private let exercises = ["Squat", "Push-up", "Deadlift", "Lunge", "Plank"]

    private var isWorkoutMode: Bool { onFinish != nil }

    // Progress value (reps or hold-seconds for plank)
    private var progressValue: Int { isPlank ? counter.holdSeconds : counter.count }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Full-screen camera feed + skeleton
            if camera.isAuthorized {
                ZStack {
                    CameraPreview(session: camera.session).ignoresSafeArea()
                    PoseOverlay(pose: camera.bodyPose).ignoresSafeArea()
                }
                // subtle top gradient so controls are readable
                LinearGradient(colors: [.black.opacity(0.55), .clear],
                               startPoint: .top, endPoint: .center)
                    .ignoresSafeArea().allowsHitTesting(false)
            } else {
                permissionView
            }

            VStack(spacing: 0) {
                topBarNew
                progressHeader
                centerFeedback
                    .padding(.top, 6)
                    .animation(.spring(response: 0.3), value: counter.formStatus)
                Spacer()
                confidenceBars
                slimControls
            }
        }
        .task {
            if let preset = presetExercise { selectedExercise = preset }
            await camera.checkPermission()
        }
        .onReceive(camera.$bodyPose) { newPose in
            if let pose = newPose {
                let action = camera.actionLabel.map {
                    ActionPrediction(label: $0,
                                     confidence: camera.actionConfidence,
                                     probabilities: camera.actionProbs)
                }
                counter.update(pose: pose, exercise: selectedExercise, action: action)
                lastPose = pose
            }
        }
        .onChange(of: counter.formStatus) { status in
            // Live cue: masalah posisi (debounced), atau postur saat plank hold.
            if status == .wrongPose || status == .notVisible
                || (isPlank && status == .straighten) {
                voice.cue(for: status)
            }
        }
        .onChange(of: counter.verdictSeq) { _ in
            // SATU verdict per rep → suara coach.
            guard let v = counter.lastVerdict else { return }
            if v == .good {
                voice.say("\(counter.count)")          // coach menghitung rep bagus
            } else if isPlank == false {
                voice.say(verdictVoice(v))
                let gen = UINotificationFeedbackGenerator()
                gen.notificationOccurred(.warning)
            }
        }
        .onChange(of: progressValue) { val in
            if let target = repTarget, val >= target, !targetReached {
                targetReached = true
                let gen = UINotificationFeedbackGenerator()
                gen.notificationOccurred(.success)
                voice.say("Great job! Target reached.")
            }
        }
        .onChange(of: selectedExercise) { _ in
            counter.reset(); targetReached = false
            ActionClassifierService.shared.reset()
            camera.actionProbs = [:]; camera.actionLabel = nil
            voice.reset()
        }
        .onDisappear {
            camera.stop()
        }
        .sheet(isPresented: $showReport) {
            if let report = report {
                FormReportView(report: report) {
                    showReport = false
                    if isWorkoutMode {
                        // Plank → kirim detik hold; lainnya → jumlah reps
                        onFinish?(isPlank ? counter.holdSeconds : counter.count)
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - New camera overlay (clean, non-obstructive)

    private var topBarNew: some View {
        HStack {
            Button { camera.stop(); dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38).background(.ultraThinMaterial).clipShape(Circle())
            }
            Spacer()
            Text(selectedExercise)
                .font(.headline.weight(.bold)).foregroundStyle(.white)
                .shadow(radius: 4)
            Spacer()
            // Voice coach toggle
            Button { voice.enabled.toggle() } label: {
                Image(systemName: voice.enabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(voice.enabled ? .black : .white)
                    .frame(width: 38, height: 38)
                    .background(voice.enabled ? AnyShapeStyle(Color.arkoLime) : AnyShapeStyle(.ultraThinMaterial))
                    .clipShape(Circle())
            }
            Button { camera.switchCamera() } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38).background(.ultraThinMaterial).clipShape(Circle())
            }
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    // Big rep/timer progress "8 / 15"
    private var progressHeader: some View {
        VStack(spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(isPlank ? timerText(progressValue) : "\(progressValue)")
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .foregroundStyle(targetReached ? Color.arkoLime : .white)
                    .contentTransition(.numericText())
                if let target = repTarget {
                    Text(isPlank ? "/ \(timerText(target))" : "/ \(target)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .shadow(color: .black.opacity(0.6), radius: 6, y: 2)
            Text(isPlank ? "hold" : "reps")
                .font(.caption).foregroundStyle(.white.opacity(0.7))
            if targetReached {
                Text("Target reached! 🎉")
                    .font(.caption.weight(.bold)).foregroundStyle(Color.arkoLime)
            }
        }
        .padding(.top, 6)
    }

    // Feedback per-rep: warning posisi (live, debounced) ATAU verdict rep terakhir.
    // Tidak ada lagi label flip-flop frame-by-frame di tengah gerakan.
    @ViewBuilder private var centerFeedback: some View {
        let live = counter.formStatus
        if live == .wrongPose || live == .notVisible {
            // Masalah posisi — card oranye/merah (sudah debounced ≥1 detik)
            VStack(spacing: 6) {
                Image(systemName: feedbackIcon(live))
                    .font(.system(size: 30, weight: .bold))
                Text(live.label)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                if let hint = feedbackHint(live) {
                    Text(hint).font(.caption).multilineTextAlignment(.center).opacity(0.9)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22).padding(.vertical, 16)
            .frame(maxWidth: 300)
            .background(statusColor(live).opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
            .transition(.scale.combined(with: .opacity))
        } else if isPlank {
            // Plank = hold → feedback live memang sesuai (bukan per-rep)
            if live == .good {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Good form")
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.arkoLime)
                .clipShape(Capsule())
            } else if live == .straighten {
                VStack(spacing: 6) {
                    Image(systemName: feedbackIcon(live))
                        .font(.system(size: 30, weight: .bold))
                    Text(live.label)
                        .font(.title3.weight(.bold))
                    Text("Keep hips level with shoulders")
                        .font(.caption).opacity(0.9)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22).padding(.vertical, 16)
                .background(statusColor(live).opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
            }
        } else if let verdict = counter.lastVerdict {
            if verdict == .good {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Good rep!")
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.arkoLime)
                .clipShape(Capsule())
                .transition(.scale.combined(with: .opacity))
                .id(counter.verdictSeq)   // re-animate tiap rep
            } else {
                VStack(spacing: 6) {
                    Image(systemName: feedbackIcon(verdict))
                        .font(.system(size: 30, weight: .bold))
                    Text(verdictTitle(verdict))
                        .font(.title3.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text(verdictHint(verdict))
                        .font(.caption).multilineTextAlignment(.center).opacity(0.9)
                    Text("Rep \(counter.count)")
                        .font(.caption2.weight(.semibold)).opacity(0.75)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22).padding(.vertical, 16)
                .frame(maxWidth: 300)
                .background(statusColor(verdict).opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
                .transition(.scale.combined(with: .opacity))
                .id(counter.verdictSeq)
            }
        }
    }

    // MARK: Verdict copy (judul / saran / suara per jenis error)

    private func verdictTitle(_ v: FormStatus) -> String {
        switch v {
        case .notDeep:       return "Too Shallow"
        case .straighten:    return "Torso Leaning"
        case .kneeAlignment: return "Knees Caving In"
        default:             return v.label
        }
    }

    private func verdictHint(_ v: FormStatus) -> String {
        switch v {
        case .notDeep:       return "Lower until your hips reach knee level"
        case .straighten:    return "Keep your chest up and back straight"
        case .kneeAlignment: return "Push your knees outward, over your toes"
        default:             return ""
        }
    }

    private func verdictVoice(_ v: FormStatus) -> String {
        switch v {
        case .notDeep:       return "Too shallow. Go deeper."
        case .straighten:    return "Torso leaning. Keep your chest up."
        case .kneeAlignment: return "Knees caving in. Push them out."
        default:             return ""
        }
    }

    private func feedbackIcon(_ s: FormStatus) -> String {
        switch s {
        case .notVisible:    return "figure.stand"
        case .lowConfidence: return "light.max"
        case .wrongPose:     return "arrow.triangle.2.circlepath"
        case .notDeep:       return "arrow.down.circle"
        case .kneeAlignment: return "arrow.left.and.right"
        case .straighten:    return "ruler"
        case .good:          return "checkmark.circle.fill"
        }
    }

    private func feedbackHint(_ s: FormStatus) -> String? {
        switch s {
        case .notVisible:    return "Step back so your whole body is in frame"
        case .lowConfidence: return "Move to a brighter spot"
        case .wrongPose:     return "Get into the \(selectedExercise.lowercased()) position"
        case .notDeep:       return "Lower a bit more for full range"
        case .kneeAlignment: return "Push your knees outward"
        case .straighten:    return "Keep hips level with shoulders"
        case .good:          return nil
        }
    }

    // Live confidence bars dari Action Classifier (per kelas) — bukti model jalan
    @ViewBuilder private var confidenceBars: some View {
        let probs = camera.actionProbs.filter { $0.key != "none" && $0.key != "other" }
        if !probs.isEmpty {
            VStack(spacing: 7) {
                ForEach(probs.sorted { $0.value > $1.value }, id: \.key) { name, val in
                    HStack(spacing: 8) {
                        Text(FeedbackMapper.title(forLabel: name))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white)
                            .frame(width: 130, alignment: .leading)
                            .lineLimit(1)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.15))
                                Capsule()
                                    .fill(barColor(name))
                                    .frame(width: geo.size.width * CGFloat(val))
                                    .animation(.easeOut(duration: 0.2), value: val)
                            }
                        }
                        .frame(height: 7)
                        Text("\(Int(val * 100))%")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func barColor(_ label: String) -> Color {
        let l = label.lowercased()
        if l.contains("correct") { return Color.arkoLime }
        if l.contains("shallow") { return .orange }
        return .red
    }

    // Slim bottom controls — feedback otomatis (tanpa tombol AI Check manual)
    private var slimControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { counter.reset(); targetReached = false } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 52, height: 50)
                        .background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Button { Task { await finishAndReport() } } label: {
                    HStack(spacing: 6) {
                        if isLoadingReport { ProgressView().tint(.black).scaleEffect(0.8) }
                        Text("Finish")
                    }
                    .font(.subheadline.weight(.bold)).foregroundStyle(.black)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(Color.arkoLime).clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(isLoadingReport)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, isWorkoutMode ? 24 : 100)
    }

    // MARK: - Bottom Panel (legacy, unused)

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            // Feedback banner (above panel)
            if let feedback = formFeedback {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(.orange)
                    Text(feedback)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            // Main frosted panel
            VStack(spacing: 16) {
                // Exercise name + form status
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedExercise)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                        HStack(spacing: 6) {
                            Circle().fill(statusColor(counter.formStatus)).frame(width: 7, height: 7)
                            Text(counter.formStatus.label)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    Spacer()
                    // Plank → hold timer | others → rep count
                    if isPlank {
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(timerText(counter.holdSeconds))
                                .font(.system(size: 46, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                            Text("hold")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    } else {
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text("\(counter.count)")
                                .font(.system(size: 52, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .contentTransition(.numericText())
                            Text("reps")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }

                // Angle + Stage pills
                HStack(spacing: 10) {
                    statPill(label: "Body Angle", value: "\(Int(counter.currentAngle))°", color: angleColor)
                    if !isPlank {
                        statPill(label: "Stage", value: counter.stage.uppercased(),
                                 color: counter.stage == "up" ? Color.arkoGreen : .orange)
                    }
                    Spacer()
                    // Pose detected indicator
                    HStack(spacing: 4) {
                        Circle()
                            .fill(camera.bodyPose != nil ? Color.arkoLime : .gray)
                            .frame(width: 6, height: 6)
                        Text(camera.bodyPose != nil ? "Tracking" : "No pose")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                // Action buttons
                if isWorkoutMode {
                    HStack(spacing: 10) {
                        // Check Form
                        Button {
                            Task { await fetchFormFeedback() }
                        } label: {
                            HStack(spacing: 6) {
                                if isLoadingFeedback {
                                    ProgressView().tint(.white).scaleEffect(0.75)
                                } else {
                                    Image(systemName: "sparkles")
                                }
                                Text("AI Form Check")
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(Color.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(isLoadingFeedback || camera.bodyPose == nil)

                        // Finish
                        Button { Task { await finishAndReport() } } label: {
                            HStack(spacing: 6) {
                                if isLoadingReport {
                                    ProgressView().tint(.black).scaleEffect(0.75)
                                }
                                Text(isPlank ? "Done  \(timerText(counter.holdSeconds))"
                                             : "Done  \(counter.count)")
                            }
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(Color.arkoLime)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(isLoadingReport)
                    }
                } else {
                    // Exercise picker + reset + report
                    VStack(spacing: 10) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(exercises, id: \.self) { ex in
                                    Button { selectedExercise = ex } label: {
                                        Text(ex)
                                            .font(.subheadline.weight(.medium))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(selectedExercise == ex
                                                        ? Color.arkoLime : Color.white.opacity(0.12))
                                            .foregroundStyle(selectedExercise == ex ? .black : .white)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        HStack(spacing: 10) {
                            Button { counter.reset() } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.counterclockwise")
                                    Text("Reset")
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(Color.white.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            if counter.count > 0 || counter.holdSeconds > 0 {
                                Button { Task { await finishAndReport() } } label: {
                                    HStack(spacing: 6) {
                                        if isLoadingReport { ProgressView().tint(.black).scaleEffect(0.75) }
                                        Text("See Report")
                                    }
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.black)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(Color.arkoLime)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                                .disabled(isLoadingReport)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .padding(.horizontal, 12)
            .padding(.bottom, isWorkoutMode ? 20 : 100)
        }
    }

    private var isPlank: Bool { selectedExercise == "Plank" }

    private func timerText(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: Live Status Badge

    private var liveStatusBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor(counter.formStatus))
                .frame(width: 10, height: 10)
            Text(counter.formStatus.label)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(statusColor(counter.formStatus).opacity(0.25))
        .overlay(
            Capsule().stroke(statusColor(counter.formStatus), lineWidth: 1.5)
        )
        .clipShape(Capsule())
        .animation(.easeInOut(duration: 0.2), value: counter.formStatus)
    }

    private func statusColor(_ status: FormStatus) -> Color {
        switch status.color {
        case "green":  return Color.arkoGreen
        case "orange": return .orange
        default:       return .red
        }
    }

    // MARK: Feedback Card

    private func feedbackCard(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.orange)
            Text(text)
                .font(.caption)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
    }

    // MARK: Rep Counter HUD

    private var counterHUD: some View {
        VStack(spacing: 6) {
            Text("\(counter.count)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
                .contentTransition(.numericText())

            Text("reps")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))

            HStack(spacing: 14) {
                statPill(label: "Angle", value: "\(Int(counter.currentAngle))°",
                         color: angleColor)
                statPill(label: "Stage", value: counter.stage.uppercased(),
                         color: counter.stage == "up" ? Color.arkoGreen : .orange)
            }
            .padding(.top, 4)

            Button {
                counter.reset()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
            .padding(.top, 8)
        }
    }

    private func statPill(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private var angleColor: Color {
        guard let config = ExerciseConfig.all[selectedExercise] else { return .white }
        if counter.currentAngle < config.downAngle { return .orange }
        if counter.currentAngle > config.upAngle { return Color.arkoGreen }
        return .yellow
    }

    // MARK: Top Bar

    private var topBar: some View {
        HStack {
            if isWorkoutMode {
                Button {
                    camera.stop()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Form Check")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text(selectedExercise)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            Button {
                camera.switchCamera()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
        }
    }

    // MARK: Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 14) {
            // Pose status
            HStack(spacing: 6) {
                Circle()
                    .fill(camera.bodyPose != nil ? Color.arkoGreen : Color.orange)
                    .frame(width: 8, height: 8)
                Text(camera.bodyPose != nil ? "Pose detected" : "Stand in frame")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())

            if isWorkoutMode {
                // Workout mode: Check Form + Done buttons
                HStack(spacing: 10) {
                    Button {
                        Task { await fetchFormFeedback() }
                    } label: {
                        HStack(spacing: 6) {
                            if isLoadingFeedback {
                                ProgressView().tint(.white).scaleEffect(0.8)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text("Check Form")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    }
                    .disabled(isLoadingFeedback || camera.bodyPose == nil)

                    Button {
                        Task { await finishAndReport() }
                    } label: {
                        HStack(spacing: 6) {
                            if isLoadingReport { ProgressView().tint(.black).scaleEffect(0.8) }
                            Text("Finish · \(counter.count)")
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.arkoLime)
                        .clipShape(Capsule())
                    }
                    .disabled(isLoadingReport)
                }
            } else {
                // Tab mode: exercise picker + finish report button
                VStack(spacing: 12) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(exercises, id: \.self) { exercise in
                                Button {
                                    selectedExercise = exercise
                                } label: {
                                    Text(exercise)
                                        .font(.subheadline.weight(.medium))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(
                                            selectedExercise == exercise
                                                ? Color.arkoLime
                                                : Color.white.opacity(0.2)
                                        )
                                        .foregroundStyle(selectedExercise == exercise ? .black : .white)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 4)
                    }

                    if counter.count > 0 {
                        Button {
                            Task { await finishAndReport() }
                        } label: {
                            HStack(spacing: 6) {
                                if isLoadingReport { ProgressView().tint(.black).scaleEffect(0.8) }
                                Image(systemName: "doc.text.magnifyingglass")
                                Text("Finish & See Report")
                            }
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.arkoLime)
                            .clipShape(Capsule())
                        }
                        .disabled(isLoadingReport)
                    }
                }
            }
        }
        .padding(.bottom, isWorkoutMode ? 30 : 90)
    }

    // MARK: Finish → Form Report (MLAgent)

    private func finishAndReport() async {
        await MainActor.run { isLoadingReport = true }
        let events = counter.formEvents.map {
            (status: $0.status.rawValue, timestamp: $0.timestamp)
        }
        // Kalau tidak ada event (mis. backend mati), buat report lokal sederhana
        do {
            let result = try await ARKOAPIService.shared.fetchFormReport(
                exercise: selectedExercise,
                events: events
            )
            await MainActor.run {
                report = result
                isLoadingReport = false
                showReport = true
            }
        } catch {
            await MainActor.run {
                report = localReport()
                isLoadingReport = false
                showReport = true
            }
        }
    }

    /// Fallback report kalau backend tidak tersedia
    private func localReport() -> FormReportResponse {
        let total = counter.formEvents.count
        let good = counter.formEvents.filter { $0.status == .good }.count
        let pct = total > 0 ? Double(good) / Double(total) * 100 : (isPlank ? 100 : 0)

        if isPlank {
            return FormReportResponse(
                exercise: selectedExercise,
                total_reps: counter.holdSeconds,
                summary: "Held a \(timerText(counter.holdSeconds)) plank. "
                    + (pct >= 80 ? "Great straight-body form!" : "Watch your hip alignment next time."),
                form_quality_pct: pct,
                issues: [],
                suggestions: ["Keep hips level with shoulders — avoid sagging or piking.",
                              "Engage your core and breathe steadily throughout the hold."]
            )
        }

        // Overall analysis: kelompokkan event per jenis error
        var counts: [FormStatus: Int] = [:]
        for e in counter.formEvents where e.status != .good {
            counts[e.status, default: 0] += 1
        }
        let issues: [FormReportIssue] = counts
            .sorted { $0.value > $1.value }
            .map { status, c in
                FormReportIssue(
                    status: status.rawValue,
                    label: status.label,
                    count: c,
                    pct: total > 0 ? Double(c) / Double(total) * 100 : 0
                )
            }

        var suggestions: [String] = []
        if counts[.notDeep] != nil { suggestions.append("Lower into a fuller range of motion each rep.") }
        if counts[.kneeAlignment] != nil { suggestions.append("Drive your knees outward, in line with your toes.") }
        if counts[.straighten] != nil { suggestions.append("Keep your back and hips aligned throughout.") }
        if suggestions.isEmpty { suggestions = ["Great consistency — keep it up!"] }

        let summary: String
        if total == 0 {
            summary = "Completed \(counter.count) reps. Stay fully in frame for form analysis."
        } else if issues.isEmpty {
            summary = "\(good)/\(total) reps with clean form — excellent work!"
        } else {
            let top = issues[0]
            summary = "\(good)/\(total) reps clean. Most common issue: \(top.label.lowercased()) (\(top.count)×)."
        }

        return FormReportResponse(
            exercise: selectedExercise,
            total_reps: max(total, counter.count),
            summary: summary,
            form_quality_pct: pct,
            issues: issues,
            suggestions: suggestions
        )
    }

    // MARK: Form Feedback (UIAgent)

    private func fetchFormFeedback() async {
        guard let pose = lastPose else { return }
        await MainActor.run { isLoadingFeedback = true }
        let keypoints = RepCounter.extractKeypoints(from: pose)  // MoveNet version
        do {
            let raw = try await ARKOAPIService.shared.analyzeForm(
                exercise: selectedExercise,
                keypoints: keypoints,
                userLevel: "beginner"
            )
            await MainActor.run {
                formFeedback = cleanFeedback(raw)
                isLoadingFeedback = false
            }
        } catch {
            await MainActor.run {
                formFeedback = "Keep your core engaged and move with control. Form looks reasonable!"
                isLoadingFeedback = false
            }
        }
    }

    /// Backend kadang balas JSON string; ambil bagian feedback yang readable.
    private func cleanFeedback(_ raw: String) -> String {
        if let range = raw.range(of: "\"feedback\""),
           let colon = raw[range.upperBound...].firstIndex(of: ":") {
            let after = raw[raw.index(after: colon)...]
            let trimmed = after.trimmingCharacters(in: CharacterSet(charactersIn: " \"{}\n"))
            if !trimmed.isEmpty { return String(trimmed.prefix(160)) }
        }
        return String(raw.prefix(160))
    }

    // MARK: Permission View

    private var permissionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.slash.fill")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.6))
            Text("Camera Access Needed")
                .font(.headline)
                .foregroundStyle(.white)
            Text(camera.errorMessage ?? "ARKO needs your camera to analyze exercise form")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
    }
}

struct FormCheckView_Previews: PreviewProvider {
    static var previews: some View {
        FormCheckView()
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - FormReportView (post-workout summary — MLAgent)
// ════════════════════════════════════════════════════════════════════════════

struct FormReportView: View {
    let report: FormReportResponse
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.arkoBg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    scoreRing
                    summaryCard
                    if !report.issues.isEmpty { issuesCard }
                    suggestionsCard
                    closeButton
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 30)
            }
        }
    }

    // MARK: Score Ring

    private var scoreRing: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 14)
                    .frame(width: 150, height: 150)
                Circle()
                    .trim(from: 0, to: report.form_quality_pct / 100)
                    .stroke(qualityColor,
                            style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .frame(width: 150, height: 150)
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int(report.form_quality_pct))%")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("form quality")
                        .font(.caption)
                        .foregroundStyle(Color.arkoTextDim)
                }
            }
            Text("\(report.exercise) Report")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text("\(report.total_reps) reps · MLAgent analysis")
                .font(.caption)
                .foregroundStyle(Color.arkoTextDim)
        }
    }

    private var qualityColor: Color {
        if report.form_quality_pct >= 80 { return Color.arkoGreen }
        if report.form_quality_pct >= 50 { return .orange }
        return .red
    }

    // MARK: Summary

    private var summaryCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.title3)
                .foregroundStyle(Color.arkoLime)
            Text(report.summary)
                .font(.subheadline)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .arkoCard()
    }

    // MARK: Issues

    private var issuesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Areas to Improve", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            ForEach(report.issues) { issue in
                HStack(spacing: 10) {
                    Text("\(Int(issue.pct))%")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                        .frame(width: 44, height: 28)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text(issue.label)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(issue.count)×")
                        .font(.caption)
                        .foregroundStyle(Color.arkoTextDim)
                }
            }
        }
        .arkoCard()
    }

    // MARK: Suggestions

    private var suggestionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Coach Tips", systemImage: "lightbulb.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.arkoLime)
            ForEach(Array(report.suggestions.enumerated()), id: \.offset) { _, tip in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.arkoLime)
                        .padding(.top, 2)
                    Text(tip)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .arkoCard()
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Text("Done")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.arkoLime)
                .clipShape(Capsule())
        }
    }
}
