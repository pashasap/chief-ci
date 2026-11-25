import Foundation
import Observation

public enum AttachmentKind: String, Codable, Equatable, Sendable {
    case photo, file, screenshot
}

public struct CaptureAttachment: Codable, Equatable, Sendable {
    public var id: UUID
    public var fileName: String
    public var kind: AttachmentKind
    public var byteCount: Int

    public init(id: UUID = UUID(), fileName: String, kind: AttachmentKind, byteCount: Int) {
        self.id = id
        self.fileName = fileName
        self.kind = kind
        self.byteCount = byteCount
    }

    public var chipLabel: String {
        "📎 \(fileName)"
    }

    public var formattedByteCount: String {
        ByteCountFormatter.string(fromByteCount: Int64(max(0, byteCount)), countStyle: .file)
    }
}

public struct CaptureComposerContext: Equatable, Sendable {
    public var heading: String
    public var editingHandle: String?
    public var attachment: CaptureAttachment?
    public var initialText: String

    public init(
        heading: String,
        editingHandle: String? = nil,
        attachment: CaptureAttachment? = nil,
        initialText: String = ""
    ) {
        self.heading = heading
        self.editingHandle = editingHandle
        self.attachment = attachment
        self.initialText = initialText
    }
}

public enum OrbRadialOption: String, CaseIterable, Equatable, Sendable {
    case keyboard
    case attachment
    case voice

    public var systemImage: String {
        switch self {
        case .keyboard: return "keyboard"
        case .attachment: return "plus"
        case .voice: return "mic"
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .keyboard: return "Keyboard Composer"
        case .attachment: return "Add Attachment + Note"
        case .voice: return "Voice Capture"
        }
    }

    public var tintToken: TokenColor {
        switch self {
        case .keyboard: return DesignTokens.glowCyan
        case .attachment: return DesignTokens.emeraldApprove
        case .voice: return DesignTokens.indigoAccent
        }
    }
}

public enum CaptureOrbMode: Equatable, Sendable {
    case idle
    case radialOpen
    case recording
    case attachmentPicker
    case keyboardComposer(CaptureComposerContext)
}

@MainActor
@Observable
public final class CaptureOrbModel {
    public private(set) var mode: CaptureOrbMode = .idle
    public private(set) var radialOptions: [OrbRadialOption] = []
    public private(set) var lastFallbackNotice: String?

    public init() {}

    public func tapOrb(availability: RecordAvailability = RecordAvailability()) {
        radialOptions = []
        if availability.isEnabled {
            lastFallbackNotice = nil
            mode = .recording
        } else {
            lastFallbackNotice = availability.reason?.text
            mode = .keyboardComposer(CaptureComposerContext(heading: "Write Capture"))
        }
    }

    public func longPressOrb() {
        lastFallbackNotice = nil
        radialOptions = [.keyboard, .attachment, .voice]
        mode = .radialOpen
    }

    public func chooseRadial(_ option: OrbRadialOption, availability: RecordAvailability = RecordAvailability()) {
        radialOptions = []
        switch option {
        case .keyboard:
            lastFallbackNotice = nil
            mode = .keyboardComposer(CaptureComposerContext(heading: "Write Capture"))
        case .attachment:
            lastFallbackNotice = nil
            mode = .attachmentPicker
        case .voice:
            tapOrb(availability: availability)
        }
    }

    public func selectAttachment(_ attachment: CaptureAttachment) {
        radialOptions = []
        lastFallbackNotice = nil
        mode = .keyboardComposer(
            CaptureComposerContext(heading: "Attachment + Note", editingHandle: nil, attachment: attachment))
    }

    public func openChangeComposer(handle: String, existingText: String) {
        radialOptions = []
        lastFallbackNotice = nil
        mode = .keyboardComposer(
            CaptureComposerContext(
                heading: "Change item", editingHandle: handle, attachment: nil, initialText: existingText))
    }

    public func dismiss() {
        radialOptions = []
        lastFallbackNotice = nil
        mode = .idle
    }

    public func discard() {
        dismiss()
    }
}
