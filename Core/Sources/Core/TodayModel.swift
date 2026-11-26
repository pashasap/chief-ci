import Foundation
import Observation

/// The Done bar: shown for `DecisionModel.undoWindow` seconds after a task is marked done.
struct DoneBarState: Equatable, Sendable {
    var handle: String
    var deadline: Date
    /// What the bar says: Kit's task-done line once the server confirmed.
    var message = "Done"
}

/// State of the Today tab: tasks done this session. Commands and their receipts live in `DecisionModel`.
@MainActor @Observable
public final class TodayModel {
    public var selectedSegment = 0
    public var moreHandle: String?
    let inbox: InboxModel
    let decisions: DecisionModel

    /// Tasks marked done this session, with the `generated_at` of the snapshot that confirmed them.
    private(set) var keptDone: [String: String] = [:]
    /// Candidates whose Augment field is open, and those awaiting a Delete confirmation.
    var augmentedIdeas: Set<String> {
        get { ideas.augmented }
        set { ideas.augmented = newValue }
    }
    var deletingIdeas: Set<String> = []
    /// The one idea model Brief and Today share.
    public let ideas: IdeaModel

    public init(inbox: InboxModel, decisions: DecisionModel, ideas: IdeaModel? = nil) {
        self.inbox = inbox
        self.decisions = decisions
        self.ideas = ideas ?? IdeaModel(inbox: inbox, decisions: decisions)
    }

    var snapshotStamp: String { inbox.snapshot?.generatedAt ?? "" }

    func isKeptDone(_ handle: String) -> Bool { keptDone[handle] == snapshotStamp && !decisions.reopenedHandles.contains(handle) }

    // MARK: Commands

    func markDone(_ handle: String) async {
        guard let task = inbox.snapshot?.tasks.first(where: { $0.handle == handle }) else { return }
        decisions.resetState(handle)
        await decisions.send("task.done", handle: handle, rev: task.rev, args: [:])
        recordIfDone(handle)
    }

    func reopen(_ handle: String) async { await decisions.undoTaskDone(handle) }

    func closeWaiting(_ handle: String) async {
        decisions.resetState(handle)
        let rev = inbox.snapshot?.waiting.first { $0.handle == handle }?.rev
        await decisions.send("waiting.close", handle: handle, rev: rev, args: [:])
    }

    func retry() async {
        let wasDone = decisions.failedCommandType == "task.done"
        let failed = (inbox.snapshot?.tasks ?? []).map(\.handle).filter { decisions.state(for: $0) == .failed }
        await decisions.retry()
        if wasDone { failed.forEach(recordIfDone) }
    }

    // MARK: Picks and candidates

    /// Removes a pick in its horizon; the row leaves at once and comes back only on failure.
    func removePick(_ handle: String, scope: PickScope) async {
        guard let task = inbox.snapshot?.tasks.first(where: { $0.handle == handle }), task.pick != nil else { return }
        decisions.resetState(handle)
        await decisions.removePick(task, scope: scope)
    }

    /// Sends one candidate decision; a pending tile allows no second one.
    func decideCandidate(_ handle: String, choice: CandidateChoice) async {
        guard let candidate = candidate(handle) else { return }
        decisions.resetState(handle)
        await decisions.decide(candidate, choice: choice)
    }

    // MARK: Ideas

    /// Opens the augmentation field of a candidate. Nothing is sent until Save.
    func openAugment(_ handle: String) {
        augmentedIdeas.insert(handle)
    }

    /// Augment's Save: a correction of the candidate, with the typed text and nothing else.
    func augmentIdea(_ handle: String, text: String) async {
        await ideas.augment(handle, text: text)
    }

    func requestDeleteIdea(_ handle: String) {
        guard decisions.canDecide, decisions.state(for: handle) == nil, candidate(handle) != nil else { return }
        deletingIdeas.insert(handle)
    }

    func cancelDeleteIdea(_ handle: String) {
        deletingIdeas.remove(handle)
    }

    /// Delete's confirmation: only the drop, and the idea stays until a snapshot omits it.
    func deleteIdea(_ handle: String) async {
        guard deletingIdeas.remove(handle) != nil, let candidate = candidate(handle) else { return }
        await decisions.drop(candidate)
    }

    /// Asks for research only while the snapshot names no queued research action.
    func researchIdea(_ handle: String) async {
        await ideas.research(handle)
    }

    private func candidate(_ handle: String) -> Candidate? {
        inbox.snapshot?.candidates.first { $0.handle == handle }
    }

    private func recordIfDone(_ handle: String) {
        guard decisions.state(for: handle) == .confirmed else { return }
        keptDone[handle] = snapshotStamp
    }
}
