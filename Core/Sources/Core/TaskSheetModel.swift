import Foundation
import Observation

/// State and commands of the task sheet. Commands go through `DecisionModel`; the confirmation and the Dropped bar
/// live there too, so every sheet instance for the same task sees them.
@MainActor @Observable
public final class TaskSheetModel {
    public var isClosed: Bool { decisions.actionSerial > openedAtSerial && decisions.shouldCloseSheet(handle: handle) }
    private let openedAtSerial: Int
    public let handle: String
    /// What the user typed in the correction field.
    public var drafts = InboxDrafts()

    let inbox: InboxModel
    let decisions: DecisionModel
    let corrections: CorrectionModel

    public init(handle: String, inbox: InboxModel, decisions: DecisionModel, corrections: CorrectionModel) {
        self.handle = handle
        self.inbox = inbox
        self.decisions = decisions
        self.corrections = corrections
        openedAtSerial = decisions.actionSerial
    }

    var minimumPickDay: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = InboxRows.timeZone(inbox.snapshot?.timezone)
        return max(inbox.snapshot?.today ?? "", formatter.string(from: decisions.now))
    }

    var task: TaskItem? { inbox.snapshot?.tasks.first { $0.handle == handle } }

    var isConfirmingDrop: Bool { decisions.dropConfirming.contains(handle) }

    var activeBar: DoneBarState? {
        guard let bar = decisions.dropBar, bar.handle == handle, decisions.now < bar.deadline else { return nil }
        return bar
    }

    // MARK: Commands

    func markDone() async { await send("task.done") }

    func reopen() async {
        decisions.dropBar = nil
        await send("task.reopen")
    }

    func requestDrop() {
        guard decisions.canDecide, decisions.isEnabled(.approve, for: handle) else { return }
        decisions.dropConfirming.insert(handle)
    }

    func cancelDrop() { decisions.dropConfirming.remove(handle) }

    func confirmDrop() async {
        guard decisions.dropConfirming.remove(handle) != nil else { return }
        guard await send("task.drop") else { return }
        decisions.dropBar = nil
    }

    func move(_ move: TaskMove) async {
        guard let when = when(for: move) else { return }
        await send("task.defer", args: ["when": when])
    }

    func pick(date: String) async {
        guard TaskDates.isValid(date), date >= minimumPickDay else { return }
        await send("task.defer", args: ["when": Self.due(date)])
    }

    func retry() async {
        await decisions.retry()
        decisions.resetState(handle)
    }

    // MARK: Helpers

    private func when(for move: TaskMove) -> JSONValue? {
        let today = inbox.snapshot?.today ?? ""
        switch move {
        case .today: return .object(["kind": .string("today"), "date": .null])
        case .later: return .object(["kind": .string("later"), "date": .null])
        case .tomorrow: return TaskDates.adding(days: 1, to: today).map(Self.due)
        case .nextWeek: return TaskDates.adding(days: 7, to: today).map(Self.due)
        case .pickDate: return nil
        }
    }

    private static func due(_ date: String) -> JSONValue {
        .object(["kind": .string("due"), "date": .string(date)])
    }

    /// Sends one task command; true when the server confirmed it.
    @discardableResult
    private func send(_ type: String, args: [String: JSONValue] = [:]) async -> Bool {
        guard let task else { return false }
        decisions.resetState(handle)
        await decisions.send(type, handle: handle, rev: task.rev, args: args)
        let confirmed = decisions.state(for: handle) == .confirmed
        decisions.resetState(handle)
        return confirmed
    }
}
