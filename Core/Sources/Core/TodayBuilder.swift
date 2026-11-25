import Foundation

/// Builds the Today segments from the cached snapshot.
@MainActor
struct TodayBuilder {
    static let emptyToday = "Nothing dated for today. Suspicious, but welcome."
    static let emptyLater = "Nothing parked for later."
    static let emptyWaiting = "You are not waiting on anyone. When you say someone owes you something, it shows here."
    static let ideasIntro = "Possible projects. Decided at the weekly review."
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    let model: TodayModel

    private var decisions: DecisionModel { model.decisions }
    private var snapshot: Snapshot? { model.inbox.snapshot }
    private var today: String { snapshot?.today ?? "" }

    func segments() -> [TodaySegment] {
        if snapshot == nil {
            return ["Today", "Later", "Waiting", "Ideas"].map {
                TodaySegment(title: $0, count: 0, emptyText: model.inbox.emptyStateText)
            }
        }
        let tasks = (snapshot?.tasks ?? []).filter(isOpenTask)
        let now = tasks.filter(isForToday)
        let later = tasks.filter { !isForToday($0) }
        return [
            taskSegment("Today", now, empty: Self.emptyToday),
            taskSegment("Later", later, empty: Self.emptyLater),
            waitingSegment(),
            ideasSegment(),
        ]
    }

    func bar() -> TodayBar? { decisions.todayBar }

    // MARK: Tasks

    private func isForToday(_ task: TaskItem) -> Bool {
        guard let when = task.when else { return false }
        if when.kind == "today" { return true }
        guard when.kind == "due", let date = when.date else { return false }
        return date <= today
    }

    private func taskSegment(_ title: String, _ tasks: [TaskItem], empty: String) -> TodaySegment {
        TodaySegment(
            title: title, count: tasks.count, tasks: tasks.map(row), emptyText: tasks.isEmpty ? empty : nil)
    }

    private func row(_ task: TaskItem) -> TodayTaskRow {
        // A tile shows its text without metadata codes and at most one action line; the codes stay in More.
        let struck = model.isKeptDone(task.handle)
        let state = decisions.state(for: task.handle)
        var row = TodayTaskRow(handle: task.handle, text: TaskTileText.text(task.text), pill: pill(task.when))
        row.overdueMark = overdue(task.when) ? "Overdue" : nil
        row.note = TaskTileText.actionSummary(task.note)
        row.noteLineLimit = row.note == nil ? nil : TaskTileText.summaryLineLimit
        row.isStruck = struck
        row.state = (state == .confirmed && !struck) ? nil : state
        row.controls = struck ? [] : taskControls(task.handle, state: state)
        return row
    }

    private func taskControls(_ handle: String, state: DecisionState?) -> [InboxControl] {
        let free = state == nil || state == .confirmed
        let done = control("Mark done", .markDone(handle), enabled: free)
        let more = InboxControl(label: "More", role: .normal, isEnabled: true, state: .idle,
            action: .taskMore(handle), icon: .more, accessibilityLabel: "More")
        return [done, more] + retryControls(handle)
    }

    private func overdue(_ when: When?) -> Bool {
        guard let when, when.kind == "due", let date = when.date else { return false }
        return date < today
    }

    func pill(_ when: When?) -> String {
        switch when?.kind {
        case "today": return "Today"
        case "later": return "Later"
        case "due": return when?.date.flatMap(Self.dayText).map { "Due " + $0 } ?? "No date"
        default: return "No date"
        }
    }

    /// "2026-11-20" reads "Nov 20".
    static func dayText(_ iso: String) -> String? {
        let parts = iso.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]),
            (1...12).contains(month)
        else { return nil }
        return "\(months[month - 1]) \(day)"
    }

    // MARK: Waiting and ideas

    static func emptyText(for segmentIndex: Int) -> String? {
        switch segmentIndex {
        case 0: return emptyToday
        case 1: return emptyLater
        case 2: return emptyWaiting
        default: return nil
        }
    }

    private func isOpenTask(_ task: TaskItem) -> Bool {
        if model.isKeptDone(task.handle) { return true }
        let state = decisions.state(for: task.handle)
        if state == .confirmed {
            if decisions.reopenedHandles.contains(task.handle) { return task.state == "open" }
            if let conf = decisions.confirmation, conf.handle == task.handle,
               conf.moment == .changeSent || conf.moment == .correctionAccepted {
                return task.state == "open"
            }
            return false
        }
        if state == .pending || state == .failed { return true }
        return task.state == "open"
    }

    private func isOpenWaiting(_ item: Waiting) -> Bool {
        let state = decisions.state(for: item.handle)
        if state == .confirmed { return false }
        if state == .pending || state == .failed { return true }
        return item.state == nil || item.state == "open"
    }

    private func waitingSegment() -> TodaySegment {
        let open = (snapshot?.waiting ?? []).filter(isOpenWaiting)
        let cards = open.map { item -> TodayWaitingCard in
            let state = decisions.state(for: item.handle)
            let close = control("Close", .closeWaiting(item.handle), enabled: state == nil || state == .confirmed)
            return TodayWaitingCard(
                handle: item.handle, text: item.text, state: state, controls: [close] + retryControls(item.handle))
        }
        return TodaySegment(
            title: "Waiting", count: cards.count, waiting: cards, emptyText: cards.isEmpty ? Self.emptyWaiting : nil)
    }

    private func ideasSegment() -> TodaySegment {
        TodayIdeaBuilder(model: model).segment()
    }

    // MARK: Controls

    private func retryControls(_ handle: String) -> [InboxControl] {
        guard decisions.retryAvailable(for: handle) else { return [] }
        return [control("Retry", .retry, enabled: true, role: .primary)]
    }

    private func control(
        _ label: String, _ action: InboxAction, enabled: Bool, role: ControlRole = .normal
    ) -> InboxControl {
        let allowed = enabled && decisions.canDecide
        return InboxControl(
            label: label, role: role, isEnabled: allowed,
            disabledReason: decisions.canDecide ? nil : decisions.cannotDecideReason,
            state: .idle, action: action, icon: SuggestionIcon.forAction(action), accessibilityLabel: label)
    }
}
