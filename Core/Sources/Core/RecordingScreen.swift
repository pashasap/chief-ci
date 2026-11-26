import Foundation

public enum ScreenScheme: Equatable, Sendable { case light, dark }

public enum RecordingAction: Equatable, Sendable { case stop, discard, typeInstead, done, write, openSettings }

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
    /// The most of the screen height the panel may take.
    public let maximumHeightFraction: Double

    public init(width: Double, height: Double, largestText: Bool, measuredBarHeight: Double? = nil) {
        self.width = width
        self.height = height
        self.largestText = largestText
        let available = max(0, height)
        let preferredBar = BottomBarMetrics.preferredHeight(width: width, height: height, largestText: largestText)
        bottomBarHeight = max(preferredBar, measuredBarHeight ?? 0)
        let aboveBar = max(0, available - bottomBarHeight)
        // Leave a real scroll viewport above the panel, even in a short landscape window.
        let backgroundReserve = min(88, (aboveBar / 3).rounded(.down))
        maximumHeightFraction = largestText ? 0.4 : 0.5
        let desired = min(
            largestText ? 420.0 : 300.0, (available * maximumHeightFraction).rounded(.down))
        panelHeight = min(desired, aboveBar - backgroundReserve)
        remainingContentHeight = aboveBar - panelHeight
    }

    /// The panel in screen coordinates: full width, directly above the bottom bar.
    public var panelFrame: LayoutFrame {
        LayoutFrame(x: 0, y: height - bottomBarHeight - panelHeight, width: width, height: panelHeight)
    }

    /// The Stop and Discard targets, stacked at the panel's bottom with a shared inset and gap.
    var controlFrames: (stop: LayoutFrame, discard: LayoutFrame) {
        let inset = RecordingMetrics.panelInset
        let target = RecordingMetrics.controlHeight
        let panel = panelFrame
        let discardY = panel.maxY - inset - target
        let stopY = discardY - RecordingMetrics.controlGap - target
        let inner = max(0, width - 2 * inset)
        return (LayoutFrame(x: inset, y: stopY, width: inner, height: target),
                LayoutFrame(x: inset, y: discardY, width: inner, height: target))
    }
}

enum RecordingMetrics {
    static let panelInset: Double = 16
    static let controlGap: Double = 8
    static let controlHeight: Double = 44
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
    public private(set) var level: Double
    public private(set) var waveformSamples: [Double]
    public let savedText: String?
    public let message: String?
    public let recoveryControls: [RecordingControl]
    public let recoveryFooterControls: [RecordingControl]
    public let transcriptLine: String?
    public let livePreviewLine: String?
    public let deliveryLine: String?
    public let controls: [RecordingControl]
    public let footerControls: [RecordingControl]
    public let confirmation: TypeInsteadConfirmation?
    public let isClosed: Bool
    public private(set) var scalableText = true
    public private(set) var wrapsWholeWords = true
    public private(set) var contentScrollable = true
    /// Stop and Discard targets in screen coordinates; set by `presented(in:)`.
    public private(set) var stopFrame = LayoutFrame(x: 0, y: 0, width: 0, height: 0)
    public private(set) var discardFrame = LayoutFrame(x: 0, y: 0, width: 0, height: 0)

    public func presented(in layout: RecordingPanelLayout) -> RecordingScreen {
        presented(in: layout, reduceMotion: false)
    }

    public func presented(in layout: RecordingPanelLayout, reduceMotion: Bool) -> RecordingScreen {
        var copy = self
        copy.level = waveformSamples.last ?? level
        let frames = layout.controlFrames
        copy.stopFrame = frames.stop
        copy.discardFrame = frames.discard
        if reduceMotion { copy.waveformSamples = [] }
        return copy
    }

    public init(model: RecordingModel) {
        let recording = model.isRecording
        let saved = model.savedMessage
        timerText = model.timerText
        waveformSamples = recording ? model.waveformSamples : []
        level = model.level
        message = model.message
        let denied = model.message == RecordingModel.microphoneDenied
        let recovery = denied ? Self.deniedControls : []
        recoveryControls = recovery
        recoveryFooterControls = denied ? Self.deniedFooterControls : []
        isClosed = model.isClosed
        statusLabel = recording ? "Recording" : nil
        statusDot = recording ? DesignTokens.recordRed : nil
        savedText = saved
        let resolvedTranscript = saved == nil ? nil : (model.isTranscribing ? "Transcribing" : (model.transcript.isEmpty ? "No transcript. The recording will be sent." : model.transcript))
        transcriptLine = resolvedTranscript
        livePreviewLine = recording ? (model.transcript.isEmpty ? "Listening" : model.transcript) : resolvedTranscript
        deliveryLine = model.deliveryLine
        controls = recovery + Self.controls(recording: recording)
        footerControls = denied ? [] : Self.footerControls(recording: recording)
        confirmation = model.isConfirmingTypeInstead
            ? (model.confirmingDiscard ? TypeInsteadConfirmation(title: "Discard this recording?",
                confirmLabel: "Discard", cancelLabel: "Keep recording") : Self.typeInsteadConfirmation) : nil
    }

    private static let typeInsteadConfirmation = TypeInsteadConfirmation(
        title: "Save this recording and write instead?",
        confirmLabel: "Type instead", cancelLabel: "Keep recording")

    private static let deniedControls = [
        RecordingControl(label: "Write", action: .write, isFullWidth: true),
        RecordingControl(label: "Open Settings", action: .openSettings, isFullWidth: false),
    ]

    private static let deniedFooterControls = [
        RecordingControl(label: "Write Capture", action: .write, isFullWidth: false),
        RecordingControl(label: "Open Settings", action: .openSettings, isFullWidth: false),
    ]

    private static func controls(recording: Bool) -> [RecordingControl] {
        if recording {
            return [
                RecordingControl(label: "Stop", action: .stop, isFullWidth: true),
                RecordingControl(label: "Discard", action: .discard, isFullWidth: false),
                RecordingControl(label: "Type instead", action: .typeInstead, isFullWidth: false),
            ]
        }
        return [RecordingControl(label: "Done", action: .done, isFullWidth: true)]
    }

    private static func footerControls(recording: Bool) -> [RecordingControl] {
        if recording {
            return [
                RecordingControl(label: "Discard", action: .discard, isFullWidth: false),
                RecordingControl(label: "Send to Kit ↑", action: .stop, isFullWidth: false),
            ]
        }
        return [RecordingControl(label: "Done", action: .done, isFullWidth: true)]
    }
}
