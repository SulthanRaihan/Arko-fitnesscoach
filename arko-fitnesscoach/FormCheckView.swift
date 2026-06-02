import SwiftUI
import AVFoundation

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Exercise Configuration (port dari Good-GYM exercises.json)
// ════════════════════════════════════════════════════════════════════════════

struct ExerciseConfig {
    let name: String
    let downAngle: Double
    let upAngle: Double
    let jointA: MoveNetPose.Joint
    let jointB: MoveNetPose.Joint  // center (vertex of angle)
    let jointC: MoveNetPose.Joint

    static let all: [String: ExerciseConfig] = [
        "Squat": ExerciseConfig(
            name: "Squat",
            downAngle: 110, upAngle: 160,
            jointA: .rightHip, jointB: .rightKnee, jointC: .rightAnkle
        ),
        "Push-up": ExerciseConfig(
            name: "Push-up",
            downAngle: 90, upAngle: 160,
            jointA: .rightShoulder, jointB: .rightElbow, jointC: .rightWrist
        ),
        "Deadlift": ExerciseConfig(
            name: "Deadlift",
            downAngle: 110, upAngle: 170,
            jointA: .rightShoulder, jointB: .rightHip, jointC: .rightKnee
        ),
        "Lunge": ExerciseConfig(
            name: "Lunge",
            downAngle: 100, upAngle: 160,
            jointA: .rightHip, jointB: .rightKnee, jointC: .rightAnkle
        ),
        "Plank": ExerciseConfig(
            name: "Plank",
            downAngle: 165, upAngle: 175,
            jointA: .rightShoulder, jointB: .rightHip, jointC: .rightAnkle
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

    var label: String {
        switch self {
        case .good:          return "Good form"
        case .notDeep:       return "Squat deeper"
        case .kneeAlignment: return "Knees out"
        case .notVisible:    return "Step into frame"
        case .lowConfidence: return "Improve lighting"
        }
    }

    var color: String {
        switch self {
        case .good:          return "green"
        case .notDeep:       return "orange"
        case .kneeAlignment: return "orange"
        case .notVisible:    return "red"
        case .lowConfidence: return "red"
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
    @Published var formStatus: FormStatus = .lowConfidence
    @Published var formEvents: [FormEvent] = []

    private var lastCountTime: TimeInterval = 0
    private let minRepInterval: TimeInterval = 0.5
    private var sessionStart = Date()

    func reset() {
        count = 0
        stage = "—"
        currentAngle = 0
        formStatus = .lowConfidence
        formEvents = []
        sessionStart = Date()
    }

    /// Update dengan MoveNet pose. Hitung rep + analisis form.
    func update(pose: MoveNetPose, exercise: String) {
        let analyzed = analyzeForm(pose: pose, exercise: exercise)
        formStatus = analyzed

        guard let config = ExerciseConfig.all[exercise],
              let a = pose.point(for: config.jointA),
              let b = pose.point(for: config.jointB),
              let c = pose.point(for: config.jointC)
        else { return }

        let angle = calculateAngle(a: a, b: b, c: c)
        currentAngle = angle

        let now = Date().timeIntervalSince1970
        if angle > config.upAngle {
            if stage == "down" && (now - lastCountTime) > minRepInterval {
                count += 1
                lastCountTime = now
                formEvents.append(FormEvent(
                    status: analyzed,
                    timestamp: Date().timeIntervalSince(sessionStart)
                ))
            }
            stage = "up"
        } else if angle < config.downAngle {
            stage = "down"
        }
    }

    /// Rule-based form analyzer — works with MoveNet 17-joint output
    private func analyzeForm(pose: MoveNetPose, exercise: String) -> FormStatus {
        guard let config = ExerciseConfig.all[exercise] else { return .lowConfidence }

        let keyJoints: [MoveNetPose.Joint] = [config.jointA, config.jointB, config.jointC,
                                               .leftHip, .rightHip]
        let avgConf = pose.avgConfidence(for: keyJoints)

        if avgConf < 0.2 { return .notVisible }
        if avgConf < 0.35 { return .lowConfidence }

        guard let a = pose.point(for: config.jointA),
              let b = pose.point(for: config.jointB),
              let c = pose.point(for: config.jointC) else { return .notVisible }

        let angle = calculateAngle(a: a, b: b, c: c)

        if exercise == "Squat" {
            if let lKnee  = pose.point(for: .leftKnee),
               let rKnee  = pose.point(for: .rightKnee),
               let lAnkle = pose.point(for: .leftAnkle),
               let rAnkle = pose.point(for: .rightAnkle) {
                let kneeWidth  = abs(lKnee.x - rKnee.x)
                let ankleWidth = abs(lAnkle.x - rAnkle.x)
                if stage == "down" && kneeWidth < ankleWidth * 0.7 { return .kneeAlignment }
            }
            if stage == "down" && angle > config.downAngle + 25 { return .notDeep }
        }
        return .good
    }

    /// Extract keypoints for UIAgent — MoveNet version
    static func extractKeypoints(from pose: MoveNetPose) -> [[String: Double]] {
        let joints: [(String, MoveNetPose.Joint)] = [
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
                "confidence": Double(pose.keypoints[pair.1.rawValue].confidence)
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

    // MoveNet replaces Apple Vision for pose detection
    @Published var moveNetPose: MoveNetPose?
    @Published var isAuthorized = false
    @Published var errorMessage: String?

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

    // MARK: MoveNet Pose Detection

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        if let pose = MoveNetDetector.shared.predict(pixelBuffer: pixelBuffer) {
            DispatchQueue.main.async { [weak self] in
                self?.moveNetPose = pose
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
    let pose: MoveNetPose?

    // MoveNet joint connections
    private let connections: [(MoveNetPose.Joint, MoveNetPose.Joint)] = [
        (.leftShoulder, .leftElbow),   (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftHip),     (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        (.leftHip, .leftKnee),         (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee),       (.rightKnee, .rightAnkle),
        (.nose, .leftEye),             (.nose, .rightEye),
    ]

    private let joints: [MoveNetPose.Joint] = [
        .nose, .leftShoulder, .rightShoulder,
        .leftElbow, .rightElbow, .leftWrist, .rightWrist,
        .leftHip, .rightHip, .leftKnee, .rightKnee,
        .leftAnkle, .rightAnkle,
    ]

    var body: some View {
        GeometryReader { _ in
            Canvas { ctx, size in
                guard let pose else { return }

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

                // Joints
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
    // Mode 1 (tab): standalone, pilih exercise sendiri
    // Mode 2 (workout): preset exercise + return rep count via onFinish
    var presetExercise: String? = nil
    var onFinish: ((Int) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraManager()
    @StateObject private var counter = RepCounter()
    @State private var selectedExercise = "Squat"
    @State private var lastPose: MoveNetPose?
    @State private var formFeedback: String?
    @State private var isLoadingFeedback = false
    @State private var report: FormReportResponse?
    @State private var showReport = false
    @State private var isLoadingReport = false

    private let exercises = ["Squat", "Push-up", "Deadlift", "Lunge", "Plank"]

    private var isWorkoutMode: Bool { onFinish != nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Camera + Pose
            if camera.isAuthorized {
                ZStack {
                    CameraPreview(session: camera.session)
                        .ignoresSafeArea()
                    PoseOverlay(pose: camera.moveNetPose)
                        .ignoresSafeArea()
                }
            } else {
                permissionView
            }

            // UI overlays
            VStack {
                topBar
                liveStatusBadge          // ← live form status (color-coded)
                Spacer()
                counterHUD
                if let feedback = formFeedback { feedbackCard(feedback) }
                Spacer()
                bottomControls
            }
            .padding()
        }
        .task {
            if let preset = presetExercise { selectedExercise = preset }
            await camera.checkPermission()
        }
        .onReceive(camera.$moveNetPose) { newPose in
            if let pose = newPose {
                counter.update(pose: pose, exercise: selectedExercise)
                lastPose = pose
            }
        }
        .onChange(of: selectedExercise) { _ in
            counter.reset()
        }
        .onDisappear {
            camera.stop()
        }
        .sheet(isPresented: $showReport) {
            if let report = report {
                FormReportView(report: report) {
                    showReport = false
                    if isWorkoutMode {
                        onFinish?(counter.count)
                        dismiss()
                    }
                }
            }
        }
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
                    .fill(camera.moveNetPose != nil ? Color.arkoGreen : Color.orange)
                    .frame(width: 8, height: 8)
                Text(camera.moveNetPose != nil ? "Pose detected" : "Stand in frame")
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
                    .disabled(isLoadingFeedback || camera.moveNetPose == nil)

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
        let pct = total > 0 ? Double(good) / Double(total) * 100 : 0
        return FormReportResponse(
            exercise: selectedExercise,
            total_reps: max(total, counter.count),
            summary: total > 0
                ? "\(good) of \(total) reps with clean form."
                : "Completed \(counter.count) reps.",
            form_quality_pct: pct,
            issues: [],
            suggestions: ["Keep practicing with full body in frame for detailed feedback."]
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
