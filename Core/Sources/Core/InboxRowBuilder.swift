import Foundation

/// How a row's controls behave, derived once per row from the decision model.
struct RowGate {
    var state: DecisionState?
    var enabled: Bool
    var reason: String?

    var controlState: ControlState {
        switch state {
        case .pending: return .pending
        case .failed: return .failed
        default: return .idle
        }
    }
}

/// What a control is, before the row's gate decides whether it is enabled.
struct ControlSpec {
    var label: String
    var action: InboxAction
    var role: ControlRole = .normal
    var blocker: String?
}

@MainActor
struct InboxRowBuilder {
    let decisions: DecisionModel
    let drafts: InboxDrafts

    func sections(inbox: InboxModel) -> [InboxSection] {
        var result: [InboxSection] = []
        let needs = needsYouRows(inbox: inbox)
        if !needs.isEmpty { result.append(InboxSection(count: inbox.needsYouCount, title: "Needs you", rows: needs)) }
        let recent = recentRows(inbox: inbox)
        if !recent.isEmpty { result.append(InboxSection(title: "Recent captures", rows: recent)) }
        return result
    }

    /// Approve and Reject are final: the Inbox never offers Undo for them (the contract has no inverse command).
    /// Done and Drop keep their own Undo on the Today and task sheet bars.
    func undoControl() -> InboxControl? { nil }

    // MARK: Rows

    private func needsYouRows(inbox: InboxModel) -> [InboxScreenRow] {
        var rows: [InboxScreenRow] = []
        let snapshot = inbox.snapshot
        for proposal in snapshot?.proposals ?? [] where isListed(proposal) {
            rows.append(proposalRow(proposal))
        }
        for question in snapshot?.questions ?? [] where isListed(question.handle, state: question.state) {
            rows.append(questionRow(question))
        }
        for line in snapshot?.unreadable ?? [] {
            rows.append(InboxScreenRow(kicker: "One line I could not read", text: line.text ?? "",
                because: "In \(line.file), line \(line.line). It has no time and no id, so it is missing from Today and from the brief.",
                lineLimit: 2))
        }
        if let skipText = InboxRows.skipText(inbox.skippedCount) {
            rows.append(InboxScreenRow(kicker: "Skipped", text: skipText))
        }
        return rows
    }

    private func recentRows(inbox: InboxModel) -> [InboxScreenRow] {
        inbox.recent.enumerated().map { index, row in
            let status = row.detail.map { row.status + ": " + $0 } ?? row.status
            var shown = InboxScreenRow(text: row.text, status: status, recentIndex: index, lineLimit: row.lineLimit)
            if let record = row.record, let uploader = inbox.uploader {
                shown.waitLine = uploader.waitLine(for: record)
                if uploader.offersRetryNow(for: record) {
                    shown.elements = [.control(InboxControl(label: UploadEngine.retryNowLabel, role: .normal,
                        isEnabled: true, state: .idle, action: .retryUpload))]
                }
            }
            if let capture = inbox.snapshot?.captures.first(where: { $0.id == row.captureId }) {
                shown.handle = capture.id
                shown.whenText = [capture.date.map(AgeText.dayHeader), capture.time].compactMap { $0 }.joined(separator: " ")
                shown.filedItems = capture.items.prefix(3).map {
                    CapturePreview(handle: $0.handle, text: $0.text, label: Self.kindLabel($0.kind))
                }
                if capture.items.count > 3 { shown.moreText = "and \(capture.items.count - 3) more" }
            } else if let record = row.record {
                shown.handle = record.clientId
                shown.whenText = AgeText.dayText(record.recordedAt, zone: .current) + " "
                    + InboxRows.clockText(record.recordedAt, in: .current)
            }
            return shown
        }
    }

    static func kindLabel(_ kind: String) -> String {
        switch kind {
        case "task": return "Task"
        case "note": return "Note"
        case "waiting": return "Waiting"
        case "idea", "candidate": return "Idea"
        case "proposal": return "Kit suggests"
        case "question": return "Kit asks"
        case "result": return "Result"
        default: return kind
        }
    }

    private func isListed(_ handle: String, state: String) -> Bool {
        state == "open" || decisions.state(for: handle) != nil
    }

    /// An approved suggestion with an action stays listed so its "Queued as" line can be shown.
    private func isListed(_ proposal: Proposal) -> Bool {
        isListed(proposal.handle, state: proposal.state) || proposal.queuedLine != nil
    }

    func gate(_ handle: String) -> RowGate {
        let state = decisions.state(for: handle)
        return RowGate(
            state: state, enabled: decisions.isEnabled(.approve, for: handle), reason: decisions.cannotDecideReason)
    }

    func proposalRow(_ proposal: Proposal) -> InboxScreenRow {
        let handle = proposal.handle
        let gate = gate(handle)
        var row = InboxScreenRow(
            kicker: "Kit suggests", text: proposal.would, because: proposal.because, handle: handle,
            state: gate.state)
        row.lineLimit = nil
        row.sourceCaptureId = proposal.capture
        row.queuedLine = proposal.queuedLine
        row.statusPosition = .belowActions
        row.decisionNotice = gate.reason
        if proposal.state != "open" && gate.state == nil { return row }
        let controls = [
            make("Approve", .approve(handle), role: .primary, gate: gate),
            make("Reject", .reject(handle), role: .destructive, gate: gate),
            make("Change", .openChange(handle), gate: gate),
        ]
        let deletion = make("Delete", .dropProposal(handle), role: .destructive, gate: gate)
        row.decisionGroup = SuggestionDecisionGroup(controls: controls, deleteControl: deletion)
        row.elements = (controls + [deletion]).map(InboxElement.control)
        if drafts.changeOpen.contains(handle) {
            row.elements += sendElements(handle, placeholder: "What should change?", action: .sendChange(handle), gate: gate)
        }
        row.elements += retryElements(handle)
        return row
    }

    func questionRow(_ question: Question) -> InboxScreenRow {
        let handle = question.handle
        let gate = gate(handle)
        var row = InboxScreenRow(
            kicker: "Kit asks", text: question.question, handle: handle, state: gate.state)
        row.lineLimit = nil
        row.sourceCaptureId = question.capture
        for (index, option) in question.options.enumerated() {
            row.elements.append(.control(make(option, .option(handle, index), gate: gate)))
        }
        row.elements += sendElements(handle, placeholder: "Type an answer", action: .sendAnswer(handle), gate: gate)
        row.elements += retryElements(handle)
        return row
    }

    func sendElements(_ handle: String, placeholder: String, action: InboxAction, gate: RowGate) -> [InboxElement] {
        let text = drafts.texts[handle] ?? ""
        let blocker = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Type something first." : nil
        let field = InboxTextField(text: text, handle: handle, placeholder: placeholder)
        let spec = ControlSpec(label: "Send", action: action, blocker: blocker)
        return [.textField(field), .control(make(spec, gate: gate))]
    }

    func retryElements(_ handle: String) -> [InboxElement] {
        guard decisions.retryAvailable(for: handle) else { return [] }
        let gate = RowGate(state: nil, enabled: decisions.canDecide, reason: decisions.cannotDecideReason)
        return [.control(make("Retry", .retry, gate: gate))]
    }

    func make(
        _ label: String, _ action: InboxAction, role: ControlRole = .normal, gate: RowGate
    ) -> InboxControl {
        make(ControlSpec(label: label, action: action, role: role), gate: gate)
    }

    func make(_ spec: ControlSpec, gate: RowGate) -> InboxControl {
        InboxControl(
            label: spec.label, role: spec.role, isEnabled: gate.enabled && spec.blocker == nil,
            disabledReason: gate.reason ?? (gate.enabled ? spec.blocker : nil), state: gate.controlState,
            action: spec.action, icon: SuggestionIcon.forAction(spec.action), accessibilityLabel: spec.label)
    }
}
