import Foundation

public enum ScreenScheme: Equatable, Sendable { case light, dark }

public enum RecordingAction: Equatable, Sendable { case stop, discard, typeInstead, done }

public struct RecordingControl: Equatable, Sendable {
    public var label: String
    public var action: RecordingAction
    public var isFullWidth: Bool
}

public struct TypeInsteadConfirmation: Equatable, Sendable {
    public var title: String
    public var confirmLabel: String
    public var cancelLabel: String
}

/// Everything the full-screen recording view shows, as plain values.
@MainActor
public struct RecordingScreen {
    public let colorScheme: ScreenScheme = .dark
    public let background = DesignTokens.recordBackground
    public let statusLabel: String?
    public let statusDot: TokenColor?
    public let timerText: String
    public let level: Double
    public let savedText: String?
    public let transcriptLine: String?
    public let deliveryLine: String?
    public let controls: [RecordingControl]
    public let confirmation: TypeInsteadConfirmation?
    public let isClosed: Bool

    public init(model: RecordingModel) {
        let recording = model.isRecording
        let saved = model.savedMessage
        timerText = model.timerText
        level = model.level
        isClosed = model.isClosed
        statusLabel = recording ? "Recording" : nil
        statusDot = recording ? DesignTokens.recordRed : nil
        savedText = saved
        transcriptLine = saved == nil ? nil : (model.isTranscribing ? "Transcribing" : (model.transcript.isEmpty ? "No transcript. The recording will be sent." : model.transcript))
        deliveryLine = model.deliveryLine
        controls = Self.controls(recording: recording, saved: saved != nil)
        confirmation = model.isConfirmingTypeInstead
            ? (model.confirmingDiscard ? TypeInsteadConfirmation(title: "Discard this recording?",
                confirmLabel: "Discard", cancelLabel: "Keep recording") : Self.typeInsteadConfirmation) : nil
    }

    private static let typeInsteadConfirmation = TypeInsteadConfirmation(
        title: "Throw away this recording and type instead?",
        confirmLabel: "Type instead", cancelLabel: "Keep recording")

    private static func controls(recording: Bool, saved: Bool) -> [RecordingControl] {
        if recording {
            return [
                RecordingControl(label: "Stop", action: .stop, isFullWidth: true),
                RecordingControl(label: "Discard", action: .discard, isFullWidth: false),
                RecordingControl(label: "Type instead", action: .typeInstead, isFullWidth: false),
            ]
        }
        return [RecordingControl(label: "Done", action: .done, isFullWidth: true)]
    }
}
