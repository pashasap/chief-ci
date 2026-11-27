import Foundation

public enum TypedCaptureAction: Equatable, Sendable { case save, cancel, recordInstead, discardDraft }

public struct TypedCaptureControl: Equatable, Sendable {
    public var label: String
    public var action: TypedCaptureAction
    public var isEnabled: Bool
    public var disabledReason: String?
}

public enum TypedFieldStyle: Equatable, Sendable { case plain }

public struct TypedCaptureField: Equatable, Sendable {
    public var style: TypedFieldStyle
    public var text: String
}

/// Everything the typed capture view shows: one plain text field and Save / Cancel or Liquid Glass footer.
@MainActor
public struct TypedCaptureScreen {
    /// The tab bar is hidden while the typed capture field is being edited.
    public static let hidesBottomBarWhileTyping = true

    /// True while the orb's composer or the type-instead composer is open.
    public static func hidesBottomBar(orbComposerOpen: Bool, typingInstead: Bool) -> Bool {
        let anyOpen = orbComposerOpen || typingInstead
        return hidesBottomBarWhileTyping && anyOpen
    }

    /// True when the orb hides the background or the type-instead composer is open.
    public static func hidesBackground(orbHidesBackground: Bool, typingInstead: Bool) -> Bool {
        orbHidesBackground || typingInstead
    }
    public let title = "Type a capture"
    public let placeholder = "What is on your mind"
    public let composerPlaceholder = "Write a thought, or describe the attachment"
    public let voiceSwitchMinimumSide = DesignTokens.minimumTapTarget
    public let heading: String
    public let attachmentChipText: String?
    public let canSend: Bool
    public let fields: [TypedCaptureField]
    public let controls: [TypedCaptureControl]
    public let footerControls: [TypedCaptureControl]
    public let message: String?

    public init(model: TypedCaptureModel, text: String, recordAvailability: RecordAvailability = .init()) {
        let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachment = model.attachment != nil
        let sendReady = !empty || hasAttachment
        heading = model.heading
        attachmentChipText = model.attachment?.chipLabel
        canSend = sendReady
        fields = [TypedCaptureField(style: .plain, text: text)]
        controls = [
            TypedCaptureControl(
                label: "Send", action: .save, isEnabled: sendReady,
                disabledReason: sendReady ? nil : "Type something first"),
            TypedCaptureControl(label: "Cancel", action: .cancel, isEnabled: true, disabledReason: nil),
            TypedCaptureControl(label: "Record instead", action: .recordInstead, isEnabled: recordAvailability.isEnabled,
                disabledReason: recordAvailability.isEnabled ? nil : recordAvailability.accessibilityLabel),
            TypedCaptureControl(label: "Discard draft", action: .discardDraft,
                isEnabled: model.draftId != nil || !text.isEmpty || hasAttachment || model.hasUnreadableDraft,
                disabledReason: nil),
        ]
        footerControls = [
            TypedCaptureControl(label: "Discard", action: .discardDraft, isEnabled: true, disabledReason: nil),
            TypedCaptureControl(
                label: "Send to Kit ↑", action: .save, isEnabled: sendReady,
                disabledReason: sendReady ? nil : "Type something first"),
        ]
        message = model.message
    }
}
