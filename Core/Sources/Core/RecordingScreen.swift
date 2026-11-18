import Foundation

public enum ScreenScheme: Equatable, Sendable { case light, dark }

public enum RecordingAction: Equatable, Sendable { case stop, discard, typeInstead, done }

public struct RecordingControl: Equatable, Sendable {
    public var label: String
    public var action: RecordingAction
    public var isFullWidth: Bool
    public var minimumTarget: Double { 44 }
    public var tint: TokenColor { isFullWidth ? DesignTokens.recordRed : DesignTokens.secondaryText }
    public var accessibilityRole: String { "button" }
    public var accessibilityLabel: String { label }
}

public struct TypeInsteadConfirmation: Equatable, Sendable {
    public var title: String
    public var confirmLabel: String
    public var cancelLabel: String
}

public enum RecordingPanelAnchor: Sendable { case bottom }
public enum RecordingPanelPresentation: Sendable { case nonmodal }

/// A bounded, scrollable panel always leaves content and the bottom bar in the layout.
public struct RecordingPanelLayout: Equatable, Sendable {
    public let width: Double
    public let height: Double
    public let largestText: Bool
    public let panelHeight: Double
    public let remainingContentHeight: Double
    public let bottomBarHeight: Double
    public let bottomBarUnobstructed = true

    public init(width: Double, height: Double, largestText: Bool) {
        self.width = width
        self.height = height
        self.largestText = largestText
        let available = max(1, height)
        bottomBarHeight = min(96, available * 0.25)
        let desired: Double = largestText ? 420 : 300
        panelHeight = min(desired, available * (width > height ? 0.48 : 0.5))
        remainingContentHeight = available - bottomBarHeight - panelHeight
    }
}

/// Everything the in-layout recording panel shows, as plain values.
@MainActor
public struct RecordingScreen {
    public let anchor: RecordingPanelAnchor = .bottom
    public let presentation: RecordingPanelPresentation = .nonmodal
    public let backgroundInteractionEnabled = true
    public let foreground = DesignTokens.recordText
    public var timerAccessibilityLabel: String { "Recording time \(timerText)" }
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
    public private(set) var scalableText = true
    public private(set) var wrapsWholeWords = true
    public private(set) var contentScrollable = true

    public func presented(in layout: RecordingPanelLayout) -> RecordingScreen {
        var copy = self
        copy.scalableText = true
        copy.wrapsWholeWords = true
        copy.contentScrollable = true
        return copy
    }

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
