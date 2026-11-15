import Foundation

public struct TodayTaskRow: Equatable, Sendable {
    public var handle: String
    public var text: String
    public var textLineLimit = 3
    public var pill: String
    public var overdueMark: String?
    public var note: String?
    public var noteLineLimit: Int?
    public var isStruck = false
    public var state: DecisionState?
    public var doneSize: Double = 44
    public var controls: [InboxControl] = []
}

public struct TodayWaitingCard: Equatable, Sendable {
    public var handle: String
    public var text: String
    public var state: DecisionState?
    public var controls: [InboxControl]
}

/// A candidate project. It has no controls: it is decided at the weekly review.
public struct TodayIdeaRow: Equatable, Sendable {
    public var handle: String
    public var text: String
    public var note: String?
}

public struct TodaySegment: Equatable, Sendable {
    public var title: String
    public var count: Int
    public var tasks: [TodayTaskRow] = []
    public var waiting: [TodayWaitingCard] = []
    public var ideas: [TodayIdeaRow] = []
    public var emptyText: String?
    public var intro: String?
}

public struct TodayBar: Equatable, Sendable {
    public var message: String
    public var undo: InboxControl
}

/// Everything the Today tab shows, as plain values. The view renders this and nothing else.
@MainActor
public struct TodayScreen {
    let model: TodayModel

    public init(model: TodayModel) { self.model = model }

    public var segmentLabel: String { "Segment" }
    public var updatedText: String { model.inbox.lastUpdatedText }

    public var header: String {
        guard let day = model.inbox.snapshot?.today else { return "Today" }
        return "Today, " + AgeText.dayHeader(day)
    }

    public var segments: [TodaySegment] { TodayBuilder(model: model).segments() }

    public var bar: TodayBar? { TodayBuilder(model: model).bar() }

    /// The offline reason, while commands are blocked.
    public var notice: String? { model.decisions.cannotDecideReason }

    public var message: String? { model.decisions.message }

    /// Kit's line after a confirmed command; the task-done line is in the Done bar instead.
    public var kitLine: String? {
        guard let line = model.decisions.activeConfirmation, line.moment != .taskDone else { return nil }
        return line.line
    }

    /// Runs what `control` stands for. A disabled control sends nothing.
    public func perform(_ control: InboxControl) async {
        guard control.isEnabled else { return }
        switch control.action {
        case .markDone(let handle): await model.markDone(handle)
        case .reopen(let handle): await model.reopen(handle)
        case .closeWaiting(let handle): await model.closeWaiting(handle)
        case .retry: await model.retry()
        default: break
        }
    }
}
