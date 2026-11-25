import Foundation
import Observation

/// One idea as every screen shows it: the same text, controls and plain status on Brief and Today.
public struct IdeaRow: Equatable, Sendable {
    public var handle: String
    public var text: String
    public var note: String?
    /// Augment, Research and Delete; Save joins them while the field is open, Retry after a failure.
    public var controls: [InboxControl] = []
    public var textField: InboxTextField?
    /// Plain status: Sending, Did not go through, the conflict line or Research queued.
    public var statusText: String?
    /// The idea ID and the queued research action, shown only under Details/More.
    public var detailsText: String?

    public var primaryStrings: [String] {
        [text, note, statusText].compactMap { $0 } + controls.map(\.label)
    }
}

/// The ONE shared idea model of Brief and Today: rows, controls and commands live here.
@MainActor @Observable
public final class IdeaModel {
    static let augmentPlaceholder = "Tell Kit what to add"
    static let queuedReason = "Research is already queued."
    static let researchQueuedText = "Research queued"

    let inbox: InboxModel
    let decisions: DecisionModel
    /// Candidates whose Augment field is open.
    var augmented: Set<String> = []

    public init(inbox: InboxModel, decisions: DecisionModel) {
        self.inbox = inbox
        self.decisions = decisions
    }

    /// Open ideas only, in snapshot order. A dispositioned idea is gone after the next snapshot.
    public var rows: [IdeaRow] {
        (inbox.snapshot?.candidates ?? []).filter { $0.state == nil || $0.state == "open" }.map(row)
    }

    func row(_ candidate: Candidate) -> IdeaRow {
        let handle = candidate.handle
        var row = IdeaRow(handle: handle, text: candidate.text, note: candidate.note)
        row.controls = controls(candidate)
        if augmented.contains(handle) {
            row.textField = InboxTextField(
                text: inbox.drafts.texts[handle] ?? "", handle: handle, placeholder: Self.augmentPlaceholder)
        }
        row.statusText = decisions.statusText(for: handle) ?? (candidate.hasResearch ? Self.researchQueuedText : nil)
        row.detailsText = ["Idea " + handle, candidate.research.flatMap { $0.isEmpty ? nil : "Research " + $0 }]
            .compactMap { $0 }.joined(separator: ", ")
        return row
    }

    // MARK: Controls

    private func controls(_ candidate: Candidate) -> [InboxControl] {
        let handle = candidate.handle
        let open = gate(handle)
        var research = open
        if candidate.hasResearch {
            research.enabled = false
            research.reason = Self.queuedReason
        }
        var result = [
            control("Augment", .augmentIdea(handle), .change, open),
            control("Research", .researchIdea(handle), .research, research),
            control("Delete", .deleteIdea(handle), .bin, open),
        ]
        if augmented.contains(handle) { result.append(control("Save", .sendCorrection(handle), .approve, open)) }
        if decisions.retryAvailable(for: handle) {
            let retry = RowGate(state: nil, enabled: decisions.canDecide, reason: decisions.cannotDecideReason)
            result.append(control("Retry", .retry, nil, retry))
        }
        return result
    }

    private func gate(_ handle: String) -> RowGate {
        RowGate(
            state: decisions.state(for: handle), enabled: decisions.isEnabled(.approve, for: handle),
            reason: decisions.cannotDecideReason)
    }

    private func control(_ label: String, _ action: InboxAction, _ icon: SuggestionIcon?, _ gate: RowGate) -> InboxControl {
        var role = ControlRole.normal
        if case .deleteIdea = action { role = .destructive }
        return InboxControl(
            label: label, role: role,
            isEnabled: gate.enabled, disabledReason: gate.reason, state: gate.controlState, action: action,
            icon: icon, accessibilityLabel: label)
    }

    // MARK: Commands

    /// Runs an idea control. Delete is silent: one tap, one command, no prompt. A disabled control sends nothing.
    public func perform(_ control: InboxControl) async {
        guard control.isEnabled else { return }
        switch control.action {
        case .augmentIdea(let handle): augmented.insert(handle)
        case .researchIdea(let handle): await research(handle)
        case .deleteIdea(let handle): await delete(handle)
        case .sendCorrection(let handle): await augment(handle, text: inbox.drafts.texts[handle] ?? "")
        case .retry: await decisions.retry()
        default: break
        }
    }

    func augment(_ handle: String, text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, decisions.canDecide,
            decisions.state(for: handle) == nil, let rev = candidate(handle)?.rev
        else { return }
        await decisions.send("item.correct", handle: handle, rev: rev, args: ["text": .string(text)])
    }

    func delete(_ handle: String) async {
        guard let candidate = candidate(handle) else { return }
        augmented.remove(handle)
        await decisions.drop(candidate)
    }

    func research(_ handle: String) async {
        guard decisions.canDecide, decisions.state(for: handle) == nil,
            let candidate = candidate(handle), !candidate.hasResearch
        else { return }
        await decisions.research(candidate)
    }

    private func candidate(_ handle: String) -> Candidate? {
        inbox.snapshot?.candidates.first { $0.handle == handle }
    }
}
