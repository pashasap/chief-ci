import Foundation

extension InboxRowBuilder {
    /// The row an item detail shows for `handle`: the Inbox row for a proposal or question,
    /// the corrections for a task or note. A handle the snapshot does not know gets disabled controls with a reason.
    func itemRow(handle: String, snapshot: Snapshot?) -> InboxScreenRow? {
        if let proposal = snapshot?.proposals.first(where: { $0.handle == handle }) { return proposalRow(proposal) }
        if let question = snapshot?.questions.first(where: { $0.handle == handle }) { return questionRow(question) }
        if let task = snapshot?.tasks.first(where: { $0.handle == handle }) {
            return correctionRow(CorrectionTarget(handle: handle, text: task.text, rev: task.rev, kind: .task))
        }
        if let note = snapshot?.notes.first(where: { $0.handle == handle }) {
            let filedAsIdea = snapshot?.captures.flatMap(\.items).contains { $0.handle == handle && $0.kind == "idea" }
            let kind: CorrectionKind = note.kind == "idea" || filedAsIdea == true ? .idea : .note
            return correctionRow(CorrectionTarget(handle: handle, text: note.text, rev: note.rev, kind: kind))
        }
        return correctionRow(CorrectionTarget(handle: handle, text: "", rev: nil, kind: nil))
    }

    /// The item kinds that decide which correction is left out: the one that would produce the current type.
    enum CorrectionKind { case task, note, idea }

    struct CorrectionTarget {
        var handle: String
        var text: String
        var rev: String?
        /// Nil when the snapshot does not know the handle.
        var kind: CorrectionKind?
    }

    static let missingItemReason = "This item is not in the latest snapshot."
    static let missingRevReason = "This item has no revision yet."

    private func correctionRow(_ target: CorrectionTarget) -> InboxScreenRow {
        let handle = target.handle
        var gate = gate(handle)
        if target.kind == nil {
            gate.enabled = false
            gate.reason = Self.missingItemReason
        } else if (target.rev ?? "").isEmpty {
            gate.enabled = false
            gate.reason = Self.missingRevReason
        }
        var row = InboxScreenRow(text: target.text, handle: handle, state: gate.state)
        // No correction turns an item into what it already is: an idea gets no "Just an idea", a task no
        // "It's a task". A plain note is neither, so it is offered both.
        if target.kind != .idea {
            row.elements.append(.control(make("Just an idea", .justAnIdea(handle), gate: gate)))
        }
        if target.kind != .task {
            row.elements.append(.control(make("It's a task", .itsATask(handle), gate: gate)))
        }
        row.elements.append(.control(make("Not this", .notThis(handle), role: .destructive, gate: gate)))
        row.elements += untouchedSendEnabled(
            sendElements(handle, placeholder: "Tell Kit what to change", action: .sendCorrection(handle), gate: gate),
            handle: handle, gate: gate)
        row.elements += retryElements(handle)
        return row
    }

    /// A correction field nobody has typed in yet is not an error: its Send stays enabled (sending nothing is a
    /// no-op). Once the draft exists and is blank, Send is disabled as usual.
    private func untouchedSendEnabled(_ elements: [InboxElement], handle: String, gate: RowGate) -> [InboxElement] {
        guard drafts.texts[handle] == nil else { return elements }
        return elements.map { element in
            guard case .control(var control) = element else { return element }
            control.isEnabled = gate.enabled
            control.disabledReason = gate.reason
            return .control(control)
        }
    }
}
