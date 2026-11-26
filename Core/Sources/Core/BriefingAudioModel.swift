import Foundation
import Observation

/// Speech synthesis port implemented by `BriefingAudioAdapter` in the App target.
public protocol BriefingSpeechPort: AnyObject, Sendable {
    func speak(
        _ text: String,
        onProgress: @escaping @Sendable (Int) -> Void,
        onFinish: @escaping @Sendable () -> Void
    )
    func stop()
}

/// Inline Daily Briefing playback state shared across Home and BriefView.
@MainActor @Observable
public final class BriefingAudioModel {
    public private(set) var isPlaying = false
    public private(set) var elapsedSeconds = 0
    public private(set) var activeScript = ""
    public let estimatedMinutes: Int

    @ObservationIgnored private let speech: any BriefingSpeechPort
    @ObservationIgnored private var playbackGeneration = 0

    public init(speech: any BriefingSpeechPort, estimatedMinutes: Int = 3) {
        self.speech = speech
        self.estimatedMinutes = max(1, estimatedMinutes)
    }

    public var statusLabel: String {
        if isPlaying { return "Playing " + formattedElapsed }
        if elapsedSeconds > 0 { return "Paused " + formattedElapsed }
        return "\(estimatedMinutes) min · Tap ▶"
    }

    public var listenButtonLabel: String {
        isPlaying ? "Pause Briefing" : "Listen (\(estimatedMinutes)m)"
    }

    public var formattedElapsed: String {
        let whole = max(0, elapsedSeconds)
        let mins = whole / 60
        let secs = whole % 60
        return secs < 10 ? "\(mins):0\(secs)" : "\(mins):\(secs)"
    }

    public func togglePlayback(script: String) {
        if isPlaying {
            playbackGeneration += 1
            speech.stop()
            isPlaying = false
            return
        }
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.split(whereSeparator: \.isNewline)
            .map { TaskTileText.text(String($0)) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let spoken = cleaned.isEmpty ? "No briefing items today." : cleaned
        if spoken != activeScript {
            elapsedSeconds = 0
            activeScript = spoken
        }
        playbackGeneration += 1
        let generation = playbackGeneration
        isPlaying = true
        speech.speak(
            spoken,
            onProgress: { [weak self] seconds in
                Task { @MainActor in
                    guard let self, self.playbackGeneration == generation, self.isPlaying else { return }
                    self.elapsedSeconds = max(0, seconds)
                }
            },
            onFinish: { [weak self] in
                Task { @MainActor in
                    guard let self, self.playbackGeneration == generation else { return }
                    self.isPlaying = false
                }
            }
        )
    }

    public func stop() {
        playbackGeneration += 1
        speech.stop()
        isPlaying = false
        elapsedSeconds = 0
    }
}
