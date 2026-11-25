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
    /// Plain status shared with the Brief; the IDs live only in `detailsText` (Details/More).
    public var statusText: String?
    public var detailsText: String?
    /// Nil at Accessibility XL: the text wraps whole.
    public var textLineLimit: Int? = 3

    public var primaryStrings: [String] {
        [text, note, statusText].compactMap { $0 } + controls.map(\.label)
    }
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

public enum TodaySegmentLayout: Equatable, Sendable { case row, stacked }

public struct TodayBar: Equatable, Sendable {
    public var message: String
    public var undo: InboxControl
}

/// Everything the Today tab shows, as plain values. The view renders this and nothing else.
@MainActor
public struct TodayScreen {
    let model: TodayModel
    private var layout: RecordingPanelLayout?
    private var activeFocus: String?
    private var activeDeferrals: TileDeferralStore?
    /// Which tiles show their whole text; a new screen model starts collapsed.
    private var expansion = TaskExpansionModel()
    public private(set) var scalableText = true
    public private(set) var wrapsWholeWords = true
    public var headerLineLimit: Int? { nil }
    /// Segments sit in one row by default and stack at Accessibility XL.
    public var segmentLayout: TodaySegmentLayout { layout?.largestText == true ? .stacked : .row }
    public var eyebrow: String { "Horizons" }
    public var heading: String {
        RootHeadingPresentation(tab: .today, contentRowCount: 4, layout: layout).headings[0].title
    }
    public var dateLabel: String? { model.inbox.snapshot?.today.map(AgeText.dayHeader) }
    public var textLineLimit: Int? { layout?.largestText == true ? nil : 3 }

    public init(model: TodayModel) { self.model = model }

    public func presented(
        in layout: RecordingPanelLayout,
        focus: String? = nil,
        deferrals: TileDeferralStore? = nil
    ) -> TodayScreen {
        var copy = self
        copy.layout = layout
        copy.activeFocus = focus
        copy.activeDeferrals = deferrals
        copy.scalableText = true
        copy.wrapsWholeWords = true
        return copy
    }

    public var segmentLabel: String { "Segment" }
    public var usesContentHeader: Bool { layout?.largestText == true }
    public var scrollsSegmentSelector: Bool { layout?.largestText == true }
    public var updatedText: String { model.inbox.lastUpdatedText }

    public var header: String {
        guard let day = model.inbox.snapshot?.today else { return "Today" }
        return "Today, " + AgeText.dayHeader(day)
    }

    public var segments: [TodaySegment] {
        let largest = layout?.largestText == true
        return TodayBuilder(model: model).segments().enumerated().map { index, segment in
            let tiles = universalTiles(for: index)
            var updated = segment
            updated.count = tiles.count
            if model.inbox.snapshot != nil {
                updated.emptyText = tiles.isEmpty ? TodayBuilder.emptyText(for: index) : nil
            }
            updated.isSelected = (index == model.selectedSegment)
            updated.lineLimit = largest ? nil : 1
            if largest {
                updated.tasks = updated.tasks.map { row in
                    var adapted = row
                    adapted.textLineLimit = nil
                    return adapted
                }
                updated.ideas = updated.ideas.map { row in
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
        case .augmentIdea, .researchIdea, .deleteIdea, .sendCorrection: await model.ideas.perform(control)
        default: break
        }
    }
}

public extension TodayScreen {
    func universalTiles(
        for segmentIndex: Int,
        framingStore: FramingSignalStore? = nil,
        deferrals: TileDeferralStore? = nil
    ) -> [UniversalTaskTile] {
        guard let bucket = Self.bucket(for: segmentIndex) else { return [] }
        let limit: Int? = layout?.largestText == true ? nil : 3
        let resolvedDeferrals = deferrals ?? activeDeferrals
        let context = TileBuildContext(
            inbox: model.inbox, decisions: model.decisions, framingStore: framingStore, deferrals: resolvedDeferrals
        ).withLineLimit(limit)
        let tiles = TaskSearchModel.corpusTiles(context: context, today: model).filter {
            $0.bucket == bucket && TaskSearchModel.matchesFocus(activeFocus, tile: $0)
        }
        return TileExpansion.tiles(tiles, expandedIDs: expansion.expandedIDs)
    }

    /// Keeps the expansion state outside the screen value, so a rebuilt screen still honours it.
    func withExpansion(_ model: TaskExpansionModel) -> TodayScreen {
        var copy = self
        copy.expansion = model
        return copy
    }

    /// Expands the tile's whole text, or collapses it back to the three-line preview.
    mutating func toggleExpansion(_ id: String) {
        expansion.toggle(id)
    }

    func performTileAction(
        _ action: TileActionKind,
        on tile: UniversalTaskTile,
        deferrals: TileDeferralStore? = nil
    ) async {
        if action == .approve, tile.sourceKind == .task {
            await model.markDone(tile.id)
            return
        }
        let context = TileBuildContext(
            inbox: model.inbox, decisions: model.decisions, deferrals: deferrals ?? activeDeferrals
        )
        await UniversalTaskTile.execute(action, on: tile, context: context)
        if action == .deferItem, model.decisions.state(for: tile.id) == .confirmed {
            model.decisions.resetState(tile.id)
        }
    }

    func submitTileChange(handle: String, sourceKind: TileSourceKind, text: String) async {
        let context = TileBuildContext(inbox: model.inbox, decisions: model.decisions)
        await UniversalTaskTile.submitChange(handle: handle, sourceKind: sourceKind, text: text, context: context)
        if model.decisions.state(for: handle) == .confirmed {
            model.decisions.resetState(handle)
        }
    }

    private static func bucket(for segmentIndex: Int) -> TileBucket? {
        switch segmentIndex {
        case 0: return .today
        case 1: return .later
        case 2: return .waiting
        case 3: return .ideas
        default: return nil
        }
    }
}
