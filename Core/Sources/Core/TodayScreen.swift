import Foundation

public struct TodayTaskRow: Equatable, Sendable {
    public var handle: String
    public var text: String
    public var textLineLimit: Int? = 3
    public var pill: String
    public var overdueMark: String?
    /// One short proposed-or-taken-action line, never a raw metadata code.
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

/// A candidate project: Augment, Research and Delete, decided at the weekly review.
public struct TodayIdeaRow: Equatable, Sendable {
    public var handle: String
    public var text: String
    public var note: String?
    /// Augment, Research and Delete; Save joins them while the correction field is open.
    public var controls: [InboxControl] = []
    /// The labelled correction field, open only after Augment.
    public var textField: InboxTextField?
    /// "Research queued as <action>" once the snapshot names the research action.
    public var queuedLine: String?
    /// The Delete confirmation, described by Core.
    public var confirmation: TaskSheetConfirmation?
}

public struct TodaySegment: Equatable, Sendable {
    public var title: String
    public var count: Int
    public var isSelected = false
    public var lineLimit: Int? = 1
    public var tasks: [TodayTaskRow] = []
    public var waiting: [TodayWaitingCard] = []
    public var ideas: [TodayIdeaRow] = []
    public var emptyText: String?
    public var intro: String?
    public var label: String { "\(title) \(count)" }
    public var accessibilityLabel: String { label }
    public var accessibilityRole: String { "button" }
    public var minimumWidth: Double { 44 }
    public var minimumHeight: Double { 44 }
}

public struct TodayBar: Equatable, Sendable {
    public var message: String
    public var undo: InboxControl
}

/// Everything the Today tab shows, as plain values. The view renders this and nothing else.
@MainActor
public struct TodayScreen {
    let model: TodayModel
    private var layout: RecordingPanelLayout?
    public private(set) var scalableText = true
    public private(set) var wrapsWholeWords = true
    public var headerLineLimit: Int? { nil }

    public init(model: TodayModel) { self.model = model }

    public func presented(in layout: RecordingPanelLayout) -> TodayScreen {
        var copy = self
        copy.layout = layout
        copy.scalableText = true
        copy.wrapsWholeWords = true
        return copy
    }

    public var segmentLabel: String { "Segment" }
    public var scrollsSegmentSelector: Bool { layout?.largestText == true }
    public var updatedText: String { model.inbox.lastUpdatedText }

    public var header: String {
        guard let day = model.inbox.snapshot?.today else { return "Today" }
        return "Today, " + AgeText.dayHeader(day)
    }

    public var segments: [TodaySegment] {
        let largest = layout?.largestText == true
        return TodayBuilder(model: model).segments().enumerated().map { index, segment in
            var updated = segment
            updated.isSelected = (index == model.selectedSegment)
            updated.lineLimit = largest ? nil : 1
            if largest {
                updated.tasks = updated.tasks.map { row in
                    var adapted = row
                    adapted.textLineLimit = nil
                    return adapted
                }
            }
            return updated
        }
    }

    public func selectSegment(_ index: Int) {
        guard (0..<4).contains(index) else { return }
        model.selectedSegment = index
    }

    public var bar: TodayBar? { TodayBuilder(model: model).bar() }

    /// The offline reason, while commands are blocked.
    public var notice: String? { model.decisions.cannotDecideReason }

    public var message: String? { model.decisions.message }

    /// Kit's line after a confirmed command; the task-done line is in the Done bar instead.
    public var kitLine: String? {
        guard let line = model.decisions.activeConfirmation, line.moment != .taskDone else { return nil }
        return line.line
    }

    /// The More sheet: the task handle, its capture and the codes its note carries.
    public var more: TaskMetadataScreen? {
        guard let handle = model.moreHandle,
            let task = model.inbox.snapshot?.tasks.first(where: { $0.handle == handle }) else { return nil }
        return TaskMetadataScreen(task: task)
    }

    /// Runs what `control` stands for. A disabled control sends nothing.
    public func perform(_ control: InboxControl) async {
        guard control.isEnabled else { return }
        switch control.action {
        case .markDone(let handle): await model.markDone(handle)
        case .reopen(let handle): await model.reopen(handle)
        case .closeWaiting(let handle): await model.closeWaiting(handle)
        case .retry: await model.retry()
        case .taskMore(let handle):
            if model.inbox.snapshot?.tasks.contains(where: { $0.handle == handle }) == true { model.moreHandle = handle }
        case .closeTaskMore: model.moreHandle = nil
        case .augmentIdea(let handle): model.openAugment(handle)
        case .researchIdea(let handle): await model.researchIdea(handle)
        case .deleteIdea(let handle): model.requestDeleteIdea(handle)
        case .cancelDeleteIdea(let handle): model.cancelDeleteIdea(handle)
        case .confirmDeleteIdea(let handle): await model.deleteIdea(handle)
        case .sendCorrection(let handle):
            await model.augmentIdea(handle, text: model.inbox.drafts.texts[handle] ?? "")
        default: break
        }
    }
}
