import AVFoundation
import Foundation

// ════════════════════════════════════════════════════════════════════════════
// MARK: - VoiceCoach
// Koreksi gerakan via suara (text-to-speech bawaan iOS). Dipanggil saat form
// status berubah jadi error. Di-throttle supaya tidak mengulang tiap frame.
// ════════════════════════════════════════════════════════════════════════════

@MainActor
final class VoiceCoach: ObservableObject {
    @Published var enabled = true

    private let synth = AVSpeechSynthesizer()
    private var lastStatus: FormStatus?
    private var lastSpoken: Date = .distantPast
    private let cooldown: TimeInterval = 3.5   // jeda minimal cue yang sama

    init() { configureSession() }

    private func configureSession() {
        // .duckOthers → pelankan musik saat ngomong; .mixWithOthers → tidak stop audio lain
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .voicePrompt, options: [.duckOthers, .mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// Cue otomatis dari status form. Hanya untuk error (good/diam → senyap).
    /// `override` dipakai kalau Action Classifier kasih kalimat kelas spesifik.
    func cue(for status: FormStatus, override: String? = nil) {
        guard enabled else { lastStatus = status; return }

        let phrase: String?
        switch status {
        case .notDeep:       phrase = override ?? "Go deeper"
        case .kneeAlignment: phrase = override ?? "Push your knees out"
        case .straighten:    phrase = override ?? "Keep your back straight"
        case .wrongPose:     phrase = "Get into position"
        case .notVisible:    phrase = "Step into the frame"
        case .good, .lowConfidence: phrase = nil
        }

        guard let phrase else { lastStatus = status; return }

        let now = Date()
        let changed = status != lastStatus
        let cooledDown = now.timeIntervalSince(lastSpoken) > cooldown
        if changed || cooledDown {
            speak(phrase)
            lastStatus = status
            lastSpoken = now
        }
    }

    /// Ucapan bebas (mis. saat target tercapai).
    func say(_ text: String) {
        guard enabled else { return }
        speak(text)
    }

    func reset() {
        lastStatus = nil
        lastSpoken = .distantPast
        synth.stopSpeaking(at: .immediate)
    }

    private func speak(_ text: String) {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: text)
        u.rate = 0.5
        u.pitchMultiplier = 1.05
        u.volume = 1.0
        u.voice = AVSpeechSynthesisVoice(language: "en-US")
        synth.speak(u)
    }
}
