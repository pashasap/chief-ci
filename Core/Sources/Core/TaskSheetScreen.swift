import Foundation

public struct TaskSheetConfirmation: Equatable, Sendable {
    public var message: String
    public var confirm: InboxControl
    public var cancel: InboxControl
}

/// Everything the task sheet shows, as plain values. The view renders this and nothing else.
@MainActor
public struct TaskSheetScreen {
    public static let droppedMessage = "Dropped. Kept in the vault, marked as dropped."
    public static let dropQuestion = "Drop this task? It stays in the vault, marked as dropped."

    let model: TaskSheetModel

    public init(model: TaskSheetModel) { self.model = model }

    public var title: String { "Task" }
    public var doneLabel: String { "Done" }
    public var dateTitle: String { "Pick a date" }
    public var cancelLabel: String { "Cancel" }
    public var moveHereLabel: String { "Move it here" }
    public var sourceLabel: String { "Source capture" }
    public var sourceCapture: Capture? { model.inbox.sourceCapture(for: model.handle) }
    public var minimumDate: Date {
        let zone = InboxRows.timeZone(model.inbox.snapshot?.timezone)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        return formatter.date(from: model.minimumPickDay) ?? model.decisions.now
    }
    public func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = InboxRows.timeZone(model.inbox.snapshot?.timezone)
        return formatter.string(from: date)
    }
    public var removeConfirmation: TaskSheetConfirmation? { detail.removeConfirmation }

    public var handle: String { model.handle }
    public var handleIsSmall: Bool { true }
    /// Nil: the full text is never clamped.
    public var lineLimit: Int? { nil }
    public var text: String { model.task?.text ?? "" }
    public var note: String? {
        guard let note = model.task?.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return note
    }
    public var moveLabel: String { "Move it" }
    public var minControlSize: Double { 44 }

    public var state: DecisionState? { model.decisions.state(for: model.handle) }
    public var notice: String? { model.decisions.cannotDecideReason }
    public var message: String? { model.decisions.message }
    /// "Sending" or "Did not go through" for this task's last command.
    public var stateCaption: String? { state == .confirmed ? nil : InboxScreenRow(text: "", state: state).stateCaption }
    /// Kit's line after a confirmed command.
    public var kitLine: String? { model.decisions.kitLine }

    private var builder: InboxRowBuilder { InboxRowBuilder(decisions: model.decisions, drafts: model.drafts) }
    private var gate: RowGate {
        var gate = builder.gate(model.handle)
        if model.task == nil {
            gate.enabled = false
            gate.reason = InboxRowBuilder.missingItemReason
        } else if (model.task?.rev ?? "").isEmpty {
            gate.enabled = false
            gate.reason = InboxRowBuilder.missingRevReason
        }
        return gate
    }

    private var detail: ItemDetailScreen {
        ItemDetailScreen(
            handle: model.handle, inbox: model.inbox, decisions: model.decisions, corrections: model.corrections,
            drafts: model.drafts)
    }

    // MARK: Controls

    /// Done or Reopen, a gap, Drop, then Retry while the last command failed.
    public var elements: [InboxElement] {
        let handle = model.handle
        let isDone = model.task?.state == "done"
        let first = isDone
            ? builder.make("Reopen", .reopen(handle), gate: gate)
            : builder.make("Done", .markDone(handle), role: .primary, gate: gate)
        let drop = builder.make("Drop", .dropTask(handle), role: .destructive, gate: gate)
        return [.control(first), .gap, .control(drop)] + builder.retryElements(handle)
    }

    public var moveChoices: [InboxControl] {
        let handle = model.handle
        let choices: [(String, TaskMove)] = [
            ("Today", .today), ("Tomorrow", .tomorrow), ("Next week", .nextWeek), ("Later", .later),
            ("Pick a date", .pickDate),
        ]
        return choices.map { builder.make($0.0, .move(handle, $0.1), gate: gate) }
    }

    /// The four V3 corrections, as the item detail shows them.
    public var corrections: [InboxControl] { detail.controls.filter { $0.action != .retry } }

    public var textField: InboxTextField? { detail.textField }

    public var confirmation: TaskSheetConfirmation? {
        guard model.isConfirmingDrop else { return nil }
        let handle = model.handle
        return TaskSheetConfirmation(
            message: Self.dropQuestion,
            confirm: builder.make("Drop it", .confirmDrop(handle), role: .destructive, gate: gate),
            cancel: builder.make("Keep it", .cancelDrop(handle), gate: RowGate(state: nil, enabled: true, reason: nil)))
    }

    public var bar: TodayBar? {
        guard let active = model.activeBar else { return nil }
        let decisions = model.decisions
        let undo = InboxControl(
            label: "Undo", role: .normal, isEnabled: decisions.canDecide, disabledReason: decisions.cannotDecideReason,
            state: .idle, action: .reopen(active.handle))
        return TodayBar(message: Self.droppedMessage, undo: undo)
    }

    // MARK: Actions

    /// Runs what `control` stands for. A disabled control sends nothing; "Pick a date" only opens the picker.
    public func perform(_ control: InboxControl) async {
        guard control.isEnabled else { return }
        switch control.action {
        case .markDone: await model.markDone()
        case .reopen: await model.reopen()
        case .dropTask: model.requestDrop()
        case .confirmDrop: await model.confirmDrop()
        case .cancelDrop: model.cancelDrop()
        case .move(_, let move): await model.move(move)
        case .retry: await model.retry()
        default:
            let drafts = model.drafts
            model.drafts = drafts.after(control.action)
            await detail.perform(control, drafts: drafts)
        }
    }

    /// A day picked in the date picker, "yyyy-MM-dd".
    public func pick(date: String) async { await model.pick(date: date) }
}
