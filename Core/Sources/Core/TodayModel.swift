import Foundation
import Observation

/// The Done bar: shown for `DecisionModel.undoWindow` seconds after a task is marked done.
struct DoneBarState: Equatable, Sendable {
    var handle: String
    var deadline: Date
    /// What the bar says: Kit's task-done line once the server confirmed.
    var message = "Done"
}

/// State of the Today tab: tasks done this session and the Done bar. Commands go through `DecisionModel`.
@MainActor @Observable
public final class TodayModel {
    public var selectedSegment = 0
    let inbox: InboxModel
    let decisions: DecisionModel

    /// Tasks marked done this session, with the `generated_at` of the snapshot that confirmed them.
    private(set) var keptDone: [String: String] = [:]
    private(set) var doneBar: DoneBarState?

    public init(inbox: InboxModel, decisions: DecisionModel) {
        self.inbox = inbox
        self.decisions = decisions
    }

    var snapshotStamp: String { inbox.snapshot?.generatedAt ?? "" }

    func isKeptDone(_ handle: String) -> Bool { keptDone[handle] == snapshotStamp && !decisions.reopenedHandles.contains(handle) }

    var activeBar: DoneBarState? {
        guard let bar = doneBar, decisions.now < bar.deadline else { return nil }
        return bar
    }

    // MARK: Commands

    func markDone(_ handle: String) async {
        guard let task = inbox.snapshot?.tasks.first(where: { $0.handle == handle }) else { return }
        decisions.resetState(handle)
        await decisions.send("task.done", handle: handle, rev: task.rev, args: [:])
        recordIfDone(handle)
    }

    func reopen(_ handle: String) async {
        guard decisions.canDecide else { return }
        let task = inbox.snapshot?.tasks.first { $0.handle == handle }
        doneBar = nil
        decisions.resetState(handle)
        await decisions.send("task.reopen", handle: handle, rev: task?.rev, args: [:])
        if decisions.state(for: handle) == .confirmed {
            keptDone[handle] = nil
            decisions.resetState(handle)
        }
    }

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

    private func recordIfDone(_ handle: String) {
        guard decisions.state(for: handle) == .confirmed else { return }
        keptDone[handle] = snapshotStamp
        var bar = DoneBarState(handle: handle, deadline: decisions.now.addingTimeInterval(DecisionModel.undoWindow))
        if let line = decisions.confirmation, line.handle == handle, line.moment == .taskDone { bar.message = line.line }
        doneBar = bar
    }
}
