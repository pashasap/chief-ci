import Foundation

/// The four dock counts, taken from the same `TaskSearchModel.corpusTiles` rows the screens render.
///
/// The lane calls `TabCounts.from(inbox:decisions:deferrals:moves:today:)`. That call is an enum case
/// with typed associated values, so no declaration carries more than four parameters: a struct copy
/// is `.fixed` and the factory case reads the corpus when its numbers are asked for.
public enum TabCounts: @unchecked Sendable {
    case fixed(home: Int, inbox: Int, tasks: Int, settings: Int)
    case from(inbox: InboxModel, decisions: DecisionModel, deferrals: TileDeferralStore?,
              moves: TileMoveStore?, today: TodayModel?)

    public init(home: Int = 0, inbox: Int = 0, tasks: Int = 0, settings: Int = 0) {
        self = .fixed(home: home, inbox: inbox, tasks: tasks, settings: settings)
    }

    @MainActor public var home: Int { parts.home }
    @MainActor public var inbox: Int { parts.inbox }
    @MainActor public var tasks: Int { parts.tasks }
    @MainActor public var settings: Int { parts.settings }

    /// The four numbers, read from the corpus rows once per access for a factory case.
    @MainActor
    private var parts: (home: Int, inbox: Int, tasks: Int, settings: Int) {
        switch self {
        case let .fixed(home, inbox, tasks, settings):
            return (home, inbox, tasks, settings)
        case let .from(inbox, decisions, deferrals, moves, today):
            let counts = TabCountReader.read(
                TabCountSource(
                    inbox: inbox, decisions: decisions,
                    deferrals: deferrals, moves: moves, today: today))
            return (counts.home, counts.inbox, counts.tasks, counts.settings)
        }
    }

    /// The buckets the Tasks tab renders: Today, Later and Ideas.
    fileprivate static let taskBuckets: Set<TileBucket> = [.today, .later, .ideas]
}

extension TabCounts: Equatable {
    /// Two factory cases are never equal: each one reads the live corpus when asked.
    public static func == (lhs: TabCounts, rhs: TabCounts) -> Bool {
        switch (lhs, rhs) {
        case let (.fixed(a, b, c, d), .fixed(e, f, g, h)):
            return (a, b, c, d) == (e, f, g, h)
        default:
            return false
        }
    }
}

/// The five things the dock counts are built from, grouped so no declaration takes five parameters.
struct TabCountSource {
    var inbox: InboxModel
    var decisions: DecisionModel
    var deferrals: TileDeferralStore?
    var moves: TileMoveStore?
    var today: TodayModel?
}

/// Home is the attention rows, Inbox the decision rows, Tasks the corpus rows, Settings the unreadable lines.
@MainActor
enum TabCountReader {
    static func read(_ source: TabCountSource) -> TabCounts {
        guard let snapshot = source.inbox.snapshot else { return TabCounts() }
        var state = TaskSearchModel.corpusState(
            snapshot: snapshot, decisions: source.decisions,
            deferrals: source.deferrals, today: source.today)
        state.movedBuckets = source.moves?.pendingMoves(decisions: source.decisions) ?? [:]
        let tiles = TaskSearchModel.corpusRows(snapshot: snapshot, state: state)
        return TabCounts(
            home: TaskSearchModel.attentionCount(snapshot: snapshot, state: state),
            inbox: decisionCount(snapshot: snapshot, state: state),
            tasks: tiles.filter { TabCounts.taskBuckets.contains($0.bucket) }.count,
            settings: snapshot.unreadable.count)
    }

    /// The Inbox's own Needs you rows: open proposals plus open questions.
    private static func decisionCount(snapshot: Snapshot, state: TileCorpusState) -> Int {
        let proposals = TaskSearchModel.inboxTiles(snapshot: snapshot, state: state)
            .filter { $0.bucket == .inbox }
            .count
        let questions = snapshot.questions.filter { question in
            state.isActionable(handle: question.handle, isOpenInSnapshot: question.state == "open")
                && !state.isDeferred(question.handle)
        }.count
        return proposals + questions
    }
}
