import Foundation

public enum ControlRole: Equatable, Sendable { case primary, normal, destructive }

public enum ControlState: Equatable, Sendable { case idle, pending, failed }

/// What a control does when tapped. Handles identify the proposal or question.
public enum InboxAction: Equatable, Hashable, Sendable {
    case approve(String)
    case reject(String)
    case dropProposal(String)
    case openChange(String)
    case sendChange(String)
    case option(String, Int)
    case sendAnswer(String)
    case retry
    case retryUpload
    case pair
    case undo
    /// Corrections of a filed task or note.
    case justAnIdea(String)
    case itsATask(String)
    case notThis(String)
    case confirmRemove(String)
    case cancelRemove(String)
    case sendCorrection(String)
    /// Today tab: task.done, task.reopen and waiting.close.
    case markDone(String)
    case reopen(String)
    case closeWaiting(String)
    case taskMore(String)
    case closeTaskMore
    /// Today Ideas: augment a candidate, research it, and delete it behind a confirmation.
    case augmentIdea(String)
    case researchIdea(String)
    case deleteIdea(String)
    case confirmDeleteIdea(String)
    case cancelDeleteIdea(String)
    /// Task sheet: drop with confirmation, and the "Move it" choices.
    case dropTask(String)
    case confirmDrop(String)
    case cancelDrop(String)
    case move(String, TaskMove)
}

/// The "Move it" choices of the task sheet.
public enum TaskMove: Equatable, Hashable, Sendable { case today, tomorrow, nextWeek, later, pickDate }

public struct InboxControl: Equatable, Sendable {
    public var label: String
    public var role: ControlRole
    public var isEnabled: Bool
    public var disabledReason: String?
    public var state: ControlState
    public var action: InboxAction
    public var icon: SuggestionIcon? = nil
    public var accessibilityLabel: String = ""
    public var minimumWidth: Double = 44
    public var minimumHeight: Double = 44
    /// Nil: a control label wraps at any text size.
    public var labelLineLimit: Int? { nil }
}

public struct InboxTextField: Equatable, Sendable {
    public var text: String
    public var handle: String
    public var placeholder: String
}

public enum InboxElement: Equatable, Sendable {
    case control(InboxControl)
    case gap
    case textField(InboxTextField)
}

public struct InboxScreenRow: Equatable, Sendable {
    public var kicker: String?
    public var text: String
    public var because: String?
    public var handle: String?
    public var state: DecisionState?
    public var elements: [InboxElement] = []
    /// Secondary line of a recent capture, and its index in `InboxModel.recent`.
    public var status: String?
    public var recentIndex: Int?
    public var lineLimit: Int? = 3
    /// Reasons stay complete independently of the row's main-text preview limit.
    public var reasonLineLimit: Int? { nil }
    public var displayedBecause: String? { isProposal ? quotedBecause : because }
    /// True for a Kit suggestion; its section carries the one "Kit suggests" label.
    public var isProposal = false
    /// Plain status: Sending, Did not go through, the conflict line or Queued.
    public var statusText: String?
    /// The item ID and queued action, shown only under Details/More.
    public var detailsText: String?
    /// Every string the primary row shows: never a per-row "Kit suggests" and never an ID.
    public var primaryStrings: [String] {
        [text, because, statusText].compactMap { $0 } + controls.map(\.label)
    }
    public var quotedBecause: String? { because.map { "You said: “" + $0 + "”" } }
    public var sourceCaptureId: String?
    public var sourceLabel: String { "Source capture" }
    public var openCaptureLabel: String { "Open capture" }
    public var decisionGroup: SuggestionDecisionGroup?
    public var statusPosition: StatusPosition = .aboveActions
    public var decisionNotice: String?
    public var stacksControls: Bool { decisionGroup == nil }
    /// Elements not already rendered by the decision group.
    public var supplementaryElements: [InboxElement] {
        guard let decisionGroup else { return elements }
        let grouped = decisionGroup.controls + [decisionGroup.deleteControl]
        return elements.filter {
            if case .control(let control) = $0 { return !grouped.contains(control) }
            return true
        }
    }
    public var whenText: String?
    public var filedItems: [CapturePreview] = []
    public var moreText: String?
    /// "Queued as <action>" for an approved suggestion that has an action.
    public var queuedLine: String?
    public var waitLine: String?

    public var controls: [InboxControl] {
        elements.compactMap { if case .control(let control) = $0 { return control } else { return nil } }
    }

    public var textField: InboxTextField? {
        elements.compactMap { if case .textField(let field) = $0 { return field } else { return nil } }.first
    }

    public var stateCaption: String? {
        switch state {
        case .pending: return "Sending"
        case .failed: return "Did not go through"
        case .confirmed: return "Done"
        case nil: return nil
        }
    }
}

public struct CapturePreview: Equatable, Sendable {
    public var handle: String
    public var text: String
    public var label: String
}

public struct InboxSection: Equatable, Sendable {
    public var count: Int? = nil
    public var headingText: String { count.map { title + " " + String($0) } ?? title }
    public var title: String
    public var rows: [InboxScreenRow]
    /// "Kit suggests" once on the section that holds suggestions; rows carry no such text.
    public var suggestionLabel: String? { rows.contains { $0.isProposal } ? KitSuggestsLabel.text : nil }
}

public enum KitSuggestsLabel { public static let text = "Kit suggests" }

/// Text the user is typing, keyed by proposal or question handle.
public struct InboxDrafts: Equatable, Sendable {
    public var changeOpen: Set<String> = []
    public var texts: [String: String] = [:]

    public init(changeOpen: Set<String> = [], texts: [String: String] = [:]) {
        self.changeOpen = changeOpen
        self.texts = texts
    }

    /// The drafts after `action` has been tapped.
    public func after(_ action: InboxAction) -> InboxDrafts {
        var next = self
        switch action {
        case .openChange(let handle):
            if next.changeOpen.contains(handle) { next.changeOpen.remove(handle) } else { next.changeOpen.insert(handle) }
        case .sendChange(let handle):
            next.changeOpen.remove(handle)
            next.texts[handle] = nil
        case .sendAnswer(let handle), .sendCorrection(let handle):
            next.texts[handle] = nil
        default: break
        }
        return next
    }
}

/// Everything the Inbox shows, as plain values. The views render this and nothing else.
@MainActor
public struct InboxScreen {
    public var title: String { "Inbox" }
    public var pairControl: InboxControl? {
        guard inbox.offersPairing else { return nil }
        return InboxControl(label: "Pair", role: .primary, isEnabled: true, state: .idle, action: .pair)
    }
    public var needsYouCount: Int { waitingCount() }

    public func waitingCount(deferrals: TileDeferralStore? = nil, focus: String? = nil) -> Int {
        guard let snapshot = inbox.snapshot else { return 0 }
        let context = TileBuildContext(inbox: inbox, decisions: decisions, deferrals: deferrals)
        let state = TaskSearchModel.corpusState(from: context)
        let proposals = TaskSearchModel.inboxTiles(snapshot: snapshot, state: state)
            .filter { $0.bucket == .inbox && TaskSearchModel.matchesFocus(focus, tile: $0) }
            .count
        let questions = snapshot.questions.filter { question in
            state.isActionable(handle: question.handle, isOpenInSnapshot: question.state == "open")
                && !state.isDeferred(question.handle)
        }.count
        return proposals + questions + snapshot.unreadable.count
    }
    public var uploadNotice: String? { inbox.uploader?.removedNotices.last }
    public let sections: [InboxSection]
    /// The offline reason, once, while decisions are blocked.
    public let notice: String?
    public let undo: InboxControl?
    public let updatedText: String
    public let infoNotice: String?
    public let emptyText: String?
    public let message: String?
    /// Kit's line after a confirmed command.
    public let kitLine: String?
    /// Shown when a snapshot is loaded and nothing is under "Needs you".
    public let needsYouEmptyText: String?

    public static let needsYouEmpty = "Nothing needs you. Enjoy it while it lasts."

    let inbox: InboxModel
    let decisions: DecisionModel
    /// Which tiles show their whole text; a screen model built over the snapshot starts collapsed.
    var expansion: TaskExpansionModel

    public var allControls: [InboxControl] {
        sections.flatMap { $0.rows }.flatMap { $0.controls } + (undo.map { [$0] } ?? [])
    }

    public init(inbox: InboxModel, decisions: DecisionModel, drafts: InboxDrafts = InboxDrafts()) {
        self.inbox = inbox
        self.decisions = decisions
        self.expansion = TaskExpansionModel()
        let builder = InboxRowBuilder(decisions: decisions, drafts: drafts)
        sections = builder.sections(inbox: inbox)
        notice = decisions.cannotDecideReason
        undo = builder.undoControl()
        updatedText = inbox.lastUpdatedText
        infoNotice = inbox.notice
        emptyText = inbox.emptyStateText
        message = decisions.message
        kitLine = decisions.kitLine
        let needsYou = sections.contains { $0.title == "Needs you" }
        needsYouEmptyText = inbox.snapshot != nil && !needsYou ? Self.needsYouEmpty : nil
    }
}

public extension InboxScreen {
    func universalTiles(
        framingStore: FramingSignalStore? = nil,
        deferrals: TileDeferralStore? = nil,
        focus: String? = nil
    ) -> [UniversalTaskTile] {
        guard let snapshot = inbox.snapshot else { return [] }
        let context = TileBuildContext(inbox: inbox, decisions: decisions, framingStore: framingStore, deferrals: deferrals)
        let tiles = TaskSearchModel.inboxTiles(snapshot: snapshot, context: context).filter {
            $0.bucket == .inbox && TaskSearchModel.matchesFocus(focus, tile: $0)
        }
        return TileExpansion.tiles(tiles, expandedIDs: expansion.expandedIDs)
    }

    /// Keeps the expansion state outside the screen value, so a rebuilt screen still honours it.
    func withExpansion(_ model: TaskExpansionModel) -> InboxScreen {
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
        let context = TileBuildContext(inbox: inbox, decisions: decisions, deferrals: deferrals)
        await UniversalTaskTile.execute(action, on: tile, context: context)
        if action == .deferItem, decisions.state(for: tile.id) == .confirmed {
            decisions.resetState(tile.id)
        }
    }

    func submitTileChange(handle: String, sourceKind: TileSourceKind, text: String) async {
        let context = TileBuildContext(inbox: inbox, decisions: decisions)
        await UniversalTaskTile.submitChange(handle: handle, sourceKind: sourceKind, text: text, context: context)
        if decisions.state(for: handle) == .confirmed {
            decisions.resetState(handle)
        }
    }
}
