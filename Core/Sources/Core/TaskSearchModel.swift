import Foundation
import Observation

/// Value snapshot of decision, deferral, and session-done flags used across tile builders.
struct TileCorpusState: Sendable {
    var confirmedHandles: Set<String> = []
    var pendingHandles: Set<String> = []
    var failedHandles: Set<String> = []
    var deferredHandles: Set<String> = []
    var keptDoneHandles: Set<String> = []
    /// Buckets a moved handle is parked in until its command settles.
    var movedBuckets: [String: TileBucket] = [:]
    var canDecide: Bool = true
    var cannotDecideReason: String? = nil
    var textLineLimit: Int? = 3

    func isActionable(handle: String, isOpenInSnapshot: Bool) -> Bool {
        if confirmedHandles.contains(handle) { return false }
        if pendingHandles.contains(handle) || failedHandles.contains(handle) { return true }
        return isOpenInSnapshot
    }

    func isDeferred(_ handle: String) -> Bool {
        deferredHandles.contains(handle)
    }
}

/// Full-corpus live search across Inbox, Today, Later, Waiting, and Ideas.
@MainActor @Observable
public final class TaskSearchModel {
    public var query: String = ""
    public var activeFocus: String? = nil

    private let inbox: InboxModel
    private let decisions: DecisionModel
    private let today: TodayModel?
    private let framingStore: FramingSignalStore?
    private let deferrals: TileDeferralStore
    private let moves = TileMoveStore()
    /// Which tiles show their whole text; a new search model starts collapsed.
    private let expansion = TaskExpansionModel()

    public init(
        inbox: InboxModel,
        decisions: DecisionModel,
        today: TodayModel? = nil,
        framingStore: FramingSignalStore? = nil
    ) {
        self.inbox = inbox
        self.decisions = decisions
        self.today = today
        self.framingStore = framingStore
        self.deferrals = TileDeferralStore()
    }

    public var context: TileBuildContext {
        var context = TileBuildContext(inbox: inbox, decisions: decisions, framingStore: framingStore, deferrals: deferrals)
        context.moves = moves
        return context
    }

    public var allTiles: [UniversalTaskTile] {
        TileExpansion.tiles(Self.corpusTiles(context: context, today: today), expandedIDs: expansion.expandedIDs)
    }

    /// Expands the tile's whole text, or collapses it back to the three-line preview.
    public func toggleExpansion(_ id: String) {
        expansion.toggle(id)
    }

    public var results: [UniversalTaskTile] {
        let base = allTiles.filter { Self.matchesFocus(activeFocus, tile: $0) }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        let needle = trimmed.lowercased()
        return base.filter { Self.matches(needle, tile: $0) }
    }

    public var statusCaption: String {
        let items = results
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Showing all \(items.count) tasks across Inbox, Today, Later, Waiting, Ideas"
        }
        return "\(items.count) matching task(s) for \"\(trimmed)\""
    }

    public func perform(_ action: TileActionKind, on tile: UniversalTaskTile) async {
        await UniversalTaskTile.execute(action, on: tile, context: context)
        if action == .deferItem, decisions.state(for: tile.id) == .confirmed {
            decisions.resetState(tile.id)
        }
    }

    public func performMove(_ target: TileMoveTarget, on tile: UniversalTaskTile) async {
        let today = inbox.snapshot?.today ?? ""
        await UniversalTaskTile.executeMove(target, on: tile, context: context, today: today)
        settleMove(tile.id)
    }

    /// After the command returns, a confirmed move leaves the snapshot in charge of the tile.
    public func settleMove(_ handle: String) {
        guard decisions.state(for: handle) == .confirmed else { return }
        moves.clear(handle)
        decisions.resetState(handle)
    }

    public func submitChange(handle: String, sourceKind: TileSourceKind, text: String) async {
        await UniversalTaskTile.submitChange(handle: handle, sourceKind: sourceKind, text: text, context: context)
        if decisions.state(for: handle) == .confirmed {
            decisions.resetState(handle)
        }
    }

    nonisolated static func matchesFocus(_ focus: String?, tile: UniversalTaskTile) -> Bool {
        guard let trimmed = focus?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return true
        }
        if let filter = FocusFilter.defaults.first(where: { $0.label.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return matchesFocusFilter(filter, tile: tile)
        }
        return matches(trimmed.lowercased(), tile: tile)
    }

    nonisolated static func matchesFocusFilter(_ filter: FocusFilter, tile: UniversalTaskTile) -> Bool {
        let text = [tile.title, tile.focusLabel ?? "", tile.metaLine].joined(separator: " ")
        return filter.matches(text: text)
    }

    nonisolated private static func matches(_ needle: String, tile: UniversalTaskTile) -> Bool {
        let haystack = [
            tile.title, tile.tagLabel, tile.focusLabel ?? "",
            tile.bucket.displayTitle, tile.bucket.rawValue,
            tile.metaLine, tile.attachmentName ?? "",
        ]
        return haystack.contains { $0.lowercased().contains(needle) }
    }

    // MARK: Shared Corpus Builders

    static func corpusState(from context: TileBuildContext, today: TodayModel? = nil) -> TileCorpusState {
        var state = corpusState(snapshot: context.inbox.snapshot, decisions: context.decisions, deferrals: context.deferrals, today: today)
        state.movedBuckets = context.moves?.pendingMoves(decisions: context.decisions) ?? [:]
        return state.withLineLimit(context.textLineLimit)
    }

    static func corpusState(
        snapshot: Snapshot?,
        decisions: DecisionModel?,
        deferrals: TileDeferralStore?,
        today: TodayModel? = nil
    ) -> TileCorpusState {
        var state = TileCorpusState(
            canDecide: decisions?.canDecide ?? true,
            cannotDecideReason: decisions?.cannotDecideReason
        )
        guard let snapshot else { return state }
        let handles = snapshot.proposals.map(\.handle) + snapshot.questions.map(\.handle)
            + snapshot.tasks.map(\.handle) + snapshot.waiting.map(\.handle) + snapshot.candidates.map(\.handle)
        for handle in handles {
            if deferrals?.isDeferred(handle) == true { state.deferredHandles.insert(handle) }
            if today?.isKeptDone(handle) == true { state.keptDoneHandles.insert(handle) }
            guard let decisionState = decisions?.state(for: handle) else { continue }
            switch decisionState {
            case .pending: state.pendingHandles.insert(handle)
            case .failed: state.failedHandles.insert(handle)
            case .confirmed:
                let isReopened = decisions?.reopenedHandles.contains(handle) == true
                let isEdit = decisions?.confirmation?.handle == handle
                    && (decisions?.confirmation?.moment == .changeSent
                        || decisions?.confirmation?.moment == .correctionAccepted)
                if !isReopened && !isEdit { state.confirmedHandles.insert(handle) }
            }
        }
        return state
    }

    static func corpusTiles(context: TileBuildContext, today: TodayModel?) -> [UniversalTaskTile] {
        guard let snapshot = context.inbox.snapshot else { return [] }
        let state = corpusState(from: context, today: today)
        return corpusTiles(snapshot: snapshot, state: state).map { applyFraming($0, store: context.framingStore) }
    }

    nonisolated static func corpusTiles(
        snapshot: Snapshot,
        state: TileCorpusState = TileCorpusState()
    ) -> [UniversalTaskTile] {
        let corpus = corpusRows(snapshot: snapshot, state: state)
        // A move in flight is the only truthful destination until the server answers.
        guard !state.movedBuckets.isEmpty else { return corpus }
        return corpus.filter { state.movedBuckets[$0.id] != nil }
    }

    /// Every corpus row, each already parked in the bucket a pending move names: no row is dropped.
    nonisolated static func corpusRows(
        snapshot: Snapshot,
        state: TileCorpusState = TileCorpusState()
    ) -> [UniversalTaskTile] {
        let inbox = inboxTiles(snapshot: snapshot, state: state)
        let todayDate = snapshot.today ?? ""
        let openTasks = snapshot.tasks.filter {
            state.keptDoneHandles.contains($0.handle)
                || state.isActionable(handle: $0.handle, isOpenInSnapshot: $0.state == "open")
        }
        let todayTasks = openTasks
            .filter { !state.isDeferred($0.handle) && isForToday($0.when, today: todayDate) }
            .map { taskTile($0, bucket: .today, todayDate: todayDate, state: state) }
        let laterTasks = openTasks
            .filter { state.isDeferred($0.handle) || !isForToday($0.when, today: todayDate) }
            .map { taskTile($0, bucket: .later, todayDate: todayDate, state: state) }
        let deferredNonTasks = inbox.filter { $0.bucket == .later }
        let remainingInbox = inbox.filter { $0.bucket == .inbox }
        let waiting = waitingTiles(snapshot: snapshot, state: state)
        let ideas = ideaTiles(snapshot: snapshot, state: state)
        return remainingInbox + todayTasks + deferredNonTasks + laterTasks
            + waiting.filter { $0.bucket == .waiting } + waiting.filter { $0.bucket == .later }
            + ideas.filter { $0.bucket == .ideas } + ideas.filter { $0.bucket == .later }
    }

    static func inboxTiles(snapshot: Snapshot, context: TileBuildContext) -> [UniversalTaskTile] {
        let state = corpusState(from: context)
        return inboxTiles(snapshot: snapshot, state: state).map { applyFraming($0, store: context.framingStore) }
    }

    nonisolated static func inboxTiles(snapshot: Snapshot, state: TileCorpusState) -> [UniversalTaskTile] {
        snapshot.proposals
            .filter { state.isActionable(handle: $0.handle, isOpenInSnapshot: $0.state == "open") }
            .map { proposal in
                let deferred = state.isDeferred(proposal.handle)
                let bucket: TileBucket = deferred ? .later : .inbox
                var tile = baseTile(id: proposal.handle, bucket: bucket, kind: .proposal, title: proposal.would)
                tile.rev = proposal.rev
                tile.tagLabel = "Proposal"
                tile.focusLabel = UniversalTaskTile.extractFocusLabel(from: proposal.because)
                tile.metaLine = deferred
                    ? "Deferred to Later"
                    : (proposal.queuedLine ?? proposal.because.map { "You said: \"\($0)\"" } ?? "Needs decision")
                tile.sourceCaptureId = proposal.capture
                return applyState(tile, state: state)
            }
    }

    nonisolated static func attentionCount(
        snapshot: Snapshot,
        state: TileCorpusState,
        focus: FocusFilter? = nil
    ) -> Int {
        let becauseMap = Dictionary(uniqueKeysWithValues: snapshot.proposals.map { ($0.handle, $0.because ?? "") })
        let proposals = inboxTiles(snapshot: snapshot, state: state).filter { tile in
            guard tile.bucket == .inbox else { return false }
            guard let focus else { return true }
            return focus.matches(text: "\(tile.title) \(becauseMap[tile.id] ?? "")")
        }.count
        let questions = snapshot.questions.filter { question in
            guard state.isActionable(handle: question.handle, isOpenInSnapshot: question.state == "open"),
                  !state.isDeferred(question.handle) else { return false }
            guard let focus else { return true }
            let combined = [question.question, question.about].compactMap { $0 }.joined(separator: " ")
            return focus.matches(text: combined)
        }.count
        let unreadable = snapshot.unreadable.filter { row in
            guard let focus else { return true }
            return focus.matches(text: "\(row.file) \(row.text ?? "")")
        }.count
        return proposals + questions + unreadable
    }

    nonisolated static func taskTile(
        _ task: TaskItem,
        bucket: TileBucket,
        todayDate: String,
        state: TileCorpusState
    ) -> UniversalTaskTile {
        let deferred = state.isDeferred(task.handle)
        let resolvedBucket: TileBucket = state.movedBuckets[task.handle] ?? (deferred ? .later : bucket)
        var tile = baseTile(id: task.handle, bucket: resolvedBucket, kind: .task, title: TaskTileText.text(task.text))
        tile.rev = task.rev
        tile.tagLabel = resolvedBucket == .today ? "Today" : "Later"
        tile.horizonIsSet = task.when != nil
        tile.focusLabel = UniversalTaskTile.extractFocusLabel(from: task.note)
        let summary = TaskTileText.actionSummary(task.note)
        tile.metaLine = deferred ? "Deferred to Later" : (summary ?? taskPill(task.when))
        tile.isStruck = state.keptDoneHandles.contains(task.handle)
        tile.overdueMark = isOverdue(task.when, today: todayDate) ? "Overdue" : nil
        tile.sourceCaptureId = task.capture
        return applyState(tile, state: state)
    }

    nonisolated static func waitingTiles(snapshot: Snapshot, state: TileCorpusState) -> [UniversalTaskTile] {
        snapshot.waiting
            .filter { state.isActionable(handle: $0.handle, isOpenInSnapshot: $0.state == nil || $0.state == "open") }
            .map { item in
                let deferred = state.isDeferred(item.handle)
                var tile = baseTile(id: item.handle, bucket: deferred ? .later : .waiting, kind: .waiting, title: item.text)
                tile.rev = item.rev
                tile.tagLabel = "Waiting"
                tile.metaLine = deferred ? "Deferred to Later" : (item.since.map { "Since \($0)" } ?? "Waiting")
                return applyState(tile, state: state)
            }
    }

    nonisolated static func ideaTiles(snapshot: Snapshot, state: TileCorpusState) -> [UniversalTaskTile] {
        snapshot.candidates
            .filter { state.isActionable(handle: $0.handle, isOpenInSnapshot: $0.state == nil || $0.state == "open") }
            .map { item in
                let deferred = state.isDeferred(item.handle)
                var tile = baseTile(
                    id: item.handle, bucket: state.movedBuckets[item.handle] ?? (deferred ? .later : .ideas),
                    kind: .candidate, title: item.text)
                tile.rev = item.rev
                tile.tagLabel = "Idea"
                tile.focusLabel = UniversalTaskTile.extractFocusLabel(from: item.note)
                tile.metaLine = deferred
                    ? "Deferred to Later"
                    : (item.hasResearch ? "Research queued" : (item.note ?? "Idea backlog"))
                return applyState(tile, state: state)
            }
    }

    nonisolated static func baseTile(id: String, bucket: TileBucket, kind: TileSourceKind, title: String) -> UniversalTaskTile {
        UniversalTaskTile(id: id, bucket: bucket, sourceKind: kind, title: title)
    }

    private static func applyFraming(_ tile: UniversalTaskTile, store: FramingSignalStore?) -> UniversalTaskTile {
        var updated = tile
        updated.framingSignal = store?.signal(for: tile.id)
        return updated
    }

    nonisolated static func applyState(_ tile: UniversalTaskTile, state: TileCorpusState) -> UniversalTaskTile {
        var updated = tile
        updated.textLineLimit = state.textLineLimit
        updated.isPending = state.pendingHandles.contains(tile.id)
        updated.isEnabled = state.canDecide && !updated.isPending
        updated.disabledReason = state.cannotDecideReason
        return updated
    }

    nonisolated private static func isForToday(_ when: When?, today: String) -> Bool {
        guard let when else { return false }
        if when.kind == "today" { return true }
        guard when.kind == "due", let date = when.date else { return false }
        return date <= today
    }

    nonisolated private static func isOverdue(_ when: When?, today: String) -> Bool {
        guard let when, when.kind == "due", let date = when.date else { return false }
        return date < today
    }

    nonisolated private static func taskPill(_ when: When?) -> String {
        switch when?.kind {
        case "today": return "Today"
        case "later": return "Later"
        case "due": return when?.date.map { "Due \($0)" } ?? "No date"
        default: return "No date"
        }
    }
}

private extension TileCorpusState {
    func withLineLimit(_ limit: Int?) -> TileCorpusState {
        var copy = self
        copy.textLineLimit = limit
        return copy
    }
}
