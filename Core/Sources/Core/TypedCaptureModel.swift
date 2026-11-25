import Foundation
import Observation

public struct ComposerEditSubmission: Equatable, Sendable {
    public var handle: String
    public var text: String

    public init(handle: String, text: String) {
        self.handle = handle
        self.text = text
    }
}

@MainActor
@Observable
public final class TypedCaptureModel {
    public private(set) var message: String?
    public private(set) var isClosed = false
    public private(set) var draftId: String?
    public private(set) var attachment: CaptureAttachment?
    public private(set) var editingHandle: String?
    public private(set) var heading = "Write Capture"
    public private(set) var lastSubmittedEdit: ComposerEditSubmission?
    public private(set) var savedAttachments: [String: CaptureAttachment] = [:]
    private var draftText = ""
    var hasUnreadableDraft: Bool { !canWriteDraft }

    public var text: String {
        get { draftText }
        set {
            guard newValue != draftText else { return }
            draftText = newValue
            if editingHandle == nil { _ = persistDraft() }
        }
    }

    @ObservationIgnored public var afterSave: (@MainActor () -> Void)?
    @ObservationIgnored public var onEditSubmit: (@MainActor (ComposerEditSubmission) async -> Void)?
    @ObservationIgnored private let store: OutboxStore
    @ObservationIgnored private let clock: any Clock
    @ObservationIgnored private let ids: any UUIDSource
    @ObservationIgnored private var persistedDraft: CaptureDraft?
    @ObservationIgnored private var canWriteDraft = true

    public init(store: OutboxStore, clock: any Clock, ids: any UUIDSource) {
        self.store = store
        self.clock = clock
        self.ids = ids
        restoreDraft()
    }

    public func apply(context: CaptureComposerContext) {
        isClosed = false
        message = nil
        heading = context.heading
        editingHandle = context.editingHandle
        attachment = context.attachment
        if context.editingHandle != nil {
            draftText = context.initialText
        } else if !context.initialText.isEmpty {
            text = context.initialText
        }
    }

    public func clearAttachment() {
        attachment = nil
    }

    public func attachment(for clientId: String) -> CaptureAttachment? {
        savedAttachments[clientId]
    }

    /// Closes the editor without discarding the draft.
    public func cancel() {
        isClosed = true
    }

    public func reopen() {
        isClosed = false
    }

    public func discardDraft() {
        if editingHandle != nil {
            clearEditor()
            isClosed = true
            message = nil
            return
        }
        do {
            try store.discardDraft()
            clearEditor()
            canWriteDraft = true
            message = nil
        } catch {
            message = "Could not discard this draft"
        }
    }

    public func save(text: String) {
        if let handle = editingHandle {
            guard let submission = prepareEdit(handle: handle, text: text) else { return }
            if let onEditSubmit { Task { await onEditSubmit(submission) } }
            return
        }
        saveNewCapture(text: text)
    }

    public func submit() async {
        if let handle = editingHandle {
            guard let submission = prepareEdit(handle: handle, text: draftText) else { return }
            await onEditSubmit?(submission)
            return
        }
        saveNewCapture(text: draftText)
    }

    public static func composeWireText(text: String, attachment: CaptureAttachment?) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let attachment else { return trimmed }
        let marker = "[Attachment: \(attachment.fileName)]"
        return trimmed.isEmpty ? marker : "\(trimmed)\n\(marker)"
    }

    public static func extractAttachmentName(from text: String) -> String? {
        guard let start = text.range(of: "[Attachment: "),
              let end = text[start.upperBound...].firstIndex(of: "]") else { return nil }
        let name = String(text[start.upperBound..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private func prepareEdit(handle: String, text: String) -> ComposerEditSubmission? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            message = "Type something first"
            return nil
        }
        let submission = ComposerEditSubmission(handle: handle, text: trimmed)
        lastSubmittedEdit = submission
        clearEditor()
        isClosed = true
        message = nil
        afterSave?()
        return submission
    }

    private func saveNewCapture(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(trimmed.isEmpty && attachment == nil) else {
            message = "Type something first"
            return
        }
        let wireText = Self.composeWireText(text: trimmed, attachment: attachment)
        draftText = text.isEmpty ? wireText : text
        guard persistDraft(), let id = draftId else { return }
        let record = OutboxRecord.typed(clientId: id, recordedAt: clock.now, text: wireText)
        do {
            try store.save(record)
        } catch {
            message = "Could not save this note"
            return
        }
        if let attachment { savedAttachments[id] = attachment }
        finishSave(id)
    }

    private func restoreDraft() {
        do {
            persistedDraft = try store.unsentDraft()
            draftId = persistedDraft?.id
            draftText = persistedDraft?.text ?? ""
        } catch {
            canWriteDraft = false
            message = "Could not read the saved draft. Discard it to start a new one."
        }
    }

    private func persistDraft() -> Bool {
        guard canWriteDraft else {
            message = "Could not save over the unreadable draft. Discard it to start a new one."
            return false
        }
        guard draftId != nil || !draftText.isEmpty else { return true }
        let id = draftId ?? ids.next().uuidString.lowercased()
        draftId = id
        let draft = CaptureDraft(id: id, text: draftText)
        do {
            if draft != persistedDraft { try store.saveDraft(draft) }
            persistedDraft = draft
            message = nil
            return true
        } catch {
            message = "Could not save this draft on this iPhone"
            return false
        }
    }

    private func finishSave(_ id: String) {
        clearEditor()
        isClosed = true
        do {
            try store.clearDraft(committedId: id)
            message = nil
        } catch {
            message = "Note saved, but its draft could not be cleared."
        }
        afterSave?()
    }

    private func clearEditor() {
        draftText = ""
        draftId = nil
        persistedDraft = nil
        attachment = nil
        editingHandle = nil
        heading = "Write Capture"
    }
}
