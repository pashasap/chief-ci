import AVFoundation
import Foundation
import Core

/// Thin AVSpeechSynthesizer adapter backing Core's BriefingAudioModel.
final class BriefingAudioAdapter: NSObject, BriefingSpeechPort, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private let queue = DispatchQueue(label: "kit.briefingAudio")
    private let lock = NSLock()

    private var timer: DispatchSourceTimer?
    private var elapsed = 0
    private var manuallyStopped = false
    private var finishHandler: (@Sendable () -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    static func selectedVoiceCandidate() -> VoiceCandidate? {
        let candidates = AVSpeechSynthesisVoice.speechVoices().map { voice in
            VoiceCandidate(
                identifier: voice.identifier,
                name: voice.name,
                language: voice.language,
                tier: qualityTier(for: voice.quality)
            )
        }
        return VoiceSelector.selectBest(from: candidates)
    }

    static func bestVoice() -> AVSpeechSynthesisVoice? {
        if let selected = selectedVoiceCandidate(),
           let voice = AVSpeechSynthesisVoice(identifier: selected.identifier) {
            return voice
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    static func selectedVoiceDisplayName() -> String {
        selectedVoiceCandidate()?.displayName ?? "System Default (en-US)"
    }

    func selectedVoiceDisplayName() -> String {
        Self.selectedVoiceDisplayName()
    }

    func speak(
        _ text: String,
        onProgress: @escaping @Sendable (Int) -> Void,
        onFinish: @escaping @Sendable () -> Void
    ) {
        stop()
        configureSession()

        lock.lock()
        manuallyStopped = false
        elapsed = 0
        finishHandler = onFinish
        lock.unlock()

        startProgressTimer(onProgress: onProgress)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func stop() {
        lock.lock()
        manuallyStopped = true
        finishHandler = nil
        let existingTimer = timer
        timer = nil
        lock.unlock()

        existingTimer?.cancel()
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        completePlayback()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        completePlayback()
    }

    private static func qualityTier(for quality: AVSpeechSynthesisVoiceQuality) -> VoiceQualityTier {
        switch quality {
        case .premium: return .premium
        case .enhanced: return .enhanced
        case .default: return .standard
        @unknown default: return .standard
        }
    }

    private func completePlayback() {
        lock.lock()
        let wasManual = manuallyStopped
        let handler = finishHandler
        finishHandler = nil
        let existingTimer = timer
        timer = nil
        lock.unlock()

        existingTimer?.cancel()
        if !wasManual { handler?() }
    }

    private func startProgressTimer(onProgress: @escaping @Sendable (Int) -> Void) {
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + 1, repeating: 1)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let stopped = self.manuallyStopped
            if !stopped { self.elapsed += 1 }
            let current = self.elapsed
            self.lock.unlock()
            if !stopped { onProgress(current) }
        }
        lock.lock()
        timer = source
        lock.unlock()
        source.resume()
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }
}
