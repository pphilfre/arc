import AVFoundation

@MainActor final class VoiceService: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let preferences: Preferences
    init(preferences: Preferences) {
        self.preferences = preferences
        super.init()
        synthesizer.delegate = self
    }
    func speak(_ text: String, alert: Bool = false) {
        guard preferences.voice != .muted, alert || preferences.voice == .full, !text.isEmpty else { return }
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .mixWithOthers])
            try audio.setActive(true)
            synthesizer.stopSpeaking(at: .immediate)
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            synthesizer.speak(utterance)
        } catch { /* Visual guidance remains available if another app owns audio. */ }
    }
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        deactivate()
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.deactivate() }
    }
    private func deactivate() {
        guard !synthesizer.isSpeaking else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
