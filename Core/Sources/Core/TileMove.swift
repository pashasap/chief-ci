import Foundation
import Observation

/// A horizon the move seam can send a tile to.
public enum TileHorizon: String, CaseIterable, Hashable, Sendable {
    case today, later, ideas

    public var label: String {
        switch self {
        case .today: return "Today"
        case .later: return "Later"
        case .ideas: return "Ideas"
        }
    }
}

/// Where a move sends a tile: one of the three horizons, or a task for one horizon.
public enum TileMoveTarget: Hashable, Sendable {
    case today, later, ideas
    case makeTask(TileHorizon)
}

/// One row of the tile's Move menu, as plain values.
public struct TileMoveOption: Hashable, Sendable {
    public var target: TileMoveTarget
    public var label: String
    public var accessibilityLabel: String

    public init(target: TileMoveTarget, label: String, accessibilityLabel: String) {
        self.target = target
        self.label = label
        self.accessibilityLabel = accessibilityLabel
    }
}

/// The one command a move sends, built from the target and the snapshot's today.
public enum TileMoveCommand {
    public static func spec(for kind: TileSourceKind, target: TileMoveTarget, today: String) -> TileCommandSpec {
        switch target {
        case .today:
            return TileCommandSpec(
                commandType: "task.defer", args: ["when": when(.string("due"), date: .string(today))],
                targetBucket: .today)
        case .later:
            return TileCommandSpec(
                commandType: "task.defer", args: ["when": when(.string("later"), date: .null)],
                targetBucket: .later)
        case .ideas:
            return TileCommandSpec(
                commandType: "item.reclassify", args: ["to": .string("idea")], targetBucket: .ideas)
        case .makeTask(let horizon):
            return makeTaskSpec(horizon, today: today)
        }
    }

    private static func makeTaskSpec(_ horizon: TileHorizon, today: String) -> TileCommandSpec {
        switch horizon {
        case .today:
            return TileCommandSpec(
                commandType: "item.reclassify",
                args: ["to": .string("task"), "when": when(.string("due"), date: .string(today))],
                targetBucket: .today)
        case .later:
            return TileCommandSpec(
                commandType: "item.reclassify",
                args: ["to": .string("task"), "when": when(.string("later"), date: .null)],
                targetBucket: .later)
        case .ideas:
            return TileCommandSpec(
                commandType: "item.reclassify", args: ["to": .string("task")], targetBucket: .ideas)
        }
    }

    private static func when(_ kind: JSONValue, date: JSONValue) -> JSONValue {
        .object(["kind": kind, "date": date])
    }
}

/// Tracks the bucket a moved tile waits in until its command settles.
@MainActor @Observable
public final class TileMoveStore {
    public static let shared = TileMoveStore()
    public private(set) var movedBuckets: [String: TileBucket] = [:]

    public init() {}

    public func markMoved(_ handle: String, to bucket: TileBucket) {
        movedBuckets[handle] = bucket
    }

    public func bucket(for handle: String) -> TileBucket? {
        movedBuckets[handle]
    }

    public func clear(_ handle: String) {
        movedBuckets[handle] = nil
    }

    /// The moves still in flight; an entry whose command settled is dropped.
    public func pendingMoves(decisions: DecisionModel) -> [String: TileBucket] {
        let settled = movedBuckets.keys.filter { decisions.state(for: $0) != .pending }
        for handle in settled { movedBuckets[handle] = nil }
        return movedBuckets
    }
}

public extension UniversalTaskTile {
    /// The move rows this tile offers, in the order the menu shows them.
    var moveOptions: [TileMoveOption] {
        switch sourceKind {
        case .task: return taskMoveOptions
        case .candidate, .note: return TileHorizon.allCases.map { option(for: .makeTask($0)) }
        default: return []
        }
    }

    /// Why the Move control is off: the tile is sending, or commands are blocked.
    var moveDisabledReason: String? {
        isPending ? "Sending" : disabledReason
    }

    private var taskMoveOptions: [TileMoveOption] {
        var options: [TileMoveOption] = []
        if bucket != .today { options.append(option(for: .today)) }
        if bucket != .later { options.append(option(for: .later)) }
        if bucket != .ideas {
            options.append(option(for: .ideas))
        } else if !horizonIsSet {
            options.append(option(for: .makeTask(.today)))
        }
        return options
    }

    private func option(for target: TileMoveTarget) -> TileMoveOption {
        TileMoveOption(
            target: target, label: Self.moveLabel(for: target),
            accessibilityLabel: Self.moveAccessibilityLabel(for: target))
    }

    static func moveLabel(for target: TileMoveTarget) -> String {
        switch target {
        case .today: return "Move to Today"
        case .later: return "Move to Later"
        case .ideas: return "Move to Ideas"
        case .makeTask: return "Make it a task"
        }
    }

    static func moveAccessibilityLabel(for target: TileMoveTarget) -> String {
        switch target {
        case .today: return "Move to Today"
        case .later: return "Move to Later"
        case .ideas: return "Move to Ideas"
        case .makeTask(let horizon): return "Make it a task for " + horizon.label
        }
    }
}

public extension UniversalTaskTile {
    /// Sends the move's one command and parks the tile in its destination until the command settles.
    @MainActor
    static func executeMove(
        _ target: TileMoveTarget, on tile: UniversalTaskTile, context: TileBuildContext, today: String
    ) async {
        let spec = TileMoveCommand.spec(for: tile.sourceKind, target: target, today: today)
        guard let commandType = spec.commandType else { return }
        let rev = tile.rev ?? lookupRev(handle: tile.id, in: context.inbox.snapshot)
        guard let rev, !rev.isEmpty else { return }
        context.decisions.resetState(tile.id)
        if let bucket = spec.targetBucket { context.moves?.markMoved(tile.id, to: bucket) }
        await context.decisions.send(commandType, handle: tile.id, rev: rev, args: spec.args)
    }
}
