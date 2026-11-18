import Foundation

/// The Ideas segment: the open candidates and the three controls each one exposes.
@MainActor
struct TodayIdeaBuilder {
    static let augmentPlaceholder = "Tell Kit what to add"
    static let deleteQuestion = "Delete this idea? It stays out of the weekly review."
    static let queuedPrefix = "Research queued as "
    static let queuedReason = "Research is already queued."

    let model: TodayModel

    private var decisions: DecisionModel { model.decisions }

    func segment() -> TodaySegment {
        let open = (model.inbox.snapshot?.candidates ?? []).filter { $0.state == nil || $0.state == "open" }
        let ideas = open.map(row)
        return TodaySegment(title: "Ideas", count: ideas.count, ideas: ideas, intro: TodayBuilder.ideasIntro)
    }

    func row(_ candidate: Candidate) -> TodayIdeaRow {
        var row = TodayIdeaRow(handle: candidate.handle, text: candidate.text, note: candidate.note)
        row.controls = controls(candidate)
        if model.augmentedIdeas.contains(candidate.handle) {
            row.textField = InboxTextField(
                text: model.inbox.drafts.texts[candidate.handle] ?? "",
                handle: candidate.handle, placeholder: Self.augmentPlaceholder)
        }
        row.queuedLine = candidate.hasResearch ? Self.queuedPrefix + (candidate.research ?? "") : nil
        row.confirmation = confirmation(candidate.handle)
        return row
    }

    // MARK: Controls

    private func controls(_ candidate: Candidate) -> [InboxControl] {
        let handle = candidate.handle
        let gate = gate(handle)
        var controls = [
            control("Augment", .augmentIdea(handle), .change, gate),
            control("Research", .researchIdea(handle), .research, researchGate(candidate)),
            control("Delete", .deleteIdea(handle), .bin, gate),
        ]
        if model.augmentedIdeas.contains(handle) {
            controls.append(control("Save", .sendCorrection(handle), .approve, gate))
        }
        if decisions.retryAvailable(for: handle) {
            controls.append(control("Retry", .retry, nil, retryGate))
        }
        return controls
    }

    private func confirmation(_ handle: String) -> TaskSheetConfirmation? {
        guard model.deletingIdeas.contains(handle) else { return nil }
        return TaskSheetConfirmation(
            message: Self.deleteQuestion,
            confirm: control("Delete it", .confirmDeleteIdea(handle), nil, gate(handle)),
            cancel: control("Keep it", .cancelDeleteIdea(handle), nil,
                RowGate(state: nil, enabled: true, reason: nil)))
    }

    /// Research is offered only while the snapshot names no research action and no command is running.
    private func researchGate(_ candidate: Candidate) -> RowGate {
        var open = gate(candidate.handle)
        if candidate.hasResearch {
            open.enabled = false
            open.reason = Self.queuedReason
        }
        return open
    }

    private func gate(_ handle: String) -> RowGate {
        RowGate(
            state: decisions.state(for: handle), enabled: decisions.isEnabled(.approve, for: handle),
            reason: decisions.cannotDecideReason)
    }

    private var retryGate: RowGate {
        RowGate(state: nil, enabled: decisions.canDecide, reason: decisions.cannotDecideReason)
    }

    private func control(
        _ label: String, _ action: InboxAction, _ icon: SuggestionIcon?, _ gate: RowGate
    ) -> InboxControl {
        InboxControl(
            label: label, role: Self.role(of: action), isEnabled: gate.enabled, disabledReason: gate.reason,
            state: gate.controlState, action: action, icon: icon, accessibilityLabel: label)
    }

    private static func role(of action: InboxAction) -> ControlRole {
        switch action {
        case .deleteIdea, .confirmDeleteIdea: return .destructive
        default: return .normal
        }
    }
}
