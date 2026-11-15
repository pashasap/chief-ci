import Foundation

public enum RecorderError: Error, Equatable, Sendable {
    case permissionDenied
}

public protocol RecorderProtocol: Sendable {
    func start(clientId: String) async throws
    func stop() async throws -> Data
    func cancel() async
    var elapsed: TimeInterval { get }
    /// The raw input level reading; the model clamps it to 0...1.
    var level: Double { get }
}

extension RecorderProtocol {
    public var level: Double { 0 }
}

/// Used for both the speech and the dictation transcriber.
public protocol TranscriberProtocol: Sendable {
    func transcribe(_ audio: Data, vocabulary: [String]) async throws -> String
}

public protocol Haptics: Sendable {
    func recordingStarted()
    func recordingSaved()
}

public protocol BackgroundLease: Sendable {
    func begin()
    func end()
}

public struct RecordingEnvironment: Sendable {
    public var clock: any Clock
    public var ids: any UUIDSource
    public var haptics: any Haptics
    public var lease: any BackgroundLease

    public init(clock: any Clock, ids: any UUIDSource, haptics: any Haptics, lease: any BackgroundLease) {
        self.clock = clock
        self.ids = ids
        self.haptics = haptics
        self.lease = lease
    }
}

public struct RecordingPipeline: Sendable {
    public var recorder: any RecorderProtocol
    public var speech: any TranscriberProtocol
    public var dictation: any TranscriberProtocol
    public var uploader: UploadEngine

    public init(
        recorder: any RecorderProtocol, speech: any TranscriberProtocol,
        dictation: any TranscriberProtocol, uploader: UploadEngine
    ) {
        self.recorder = recorder
        self.speech = speech
        self.dictation = dictation
        self.uploader = uploader
    }
}

/// Result of running both transcribers on one recording.
struct TranscriptionOutcome: Equatable {
    var text: String
    var transcriber: String
    var alt: OutboxAlt?

    static let none = TranscriptionOutcome(text: "", transcriber: "none", alt: nil)

    static func combine(speech: String?, dictation: String?) -> TranscriptionOutcome {
        if let speech, !speech.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let alt = dictation.map { OutboxAlt(transcriber: "dictation", text: $0) }
            return TranscriptionOutcome(text: speech, transcriber: "speech", alt: alt)
        }
        if let dictation, !dictation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return TranscriptionOutcome(text: dictation, transcriber: "dictation", alt: nil)
        }
        return .none
    }
}

enum TimerFormat {
    static func text(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds))
        return "\(whole / 60):" + (whole % 60 < 10 ? "0" : "") + "\(whole % 60)"
    }
}
