import Foundation
import Observation

public enum TileBucket: String, Codable, CaseIterable, Equatable, Sendable {
    case inbox, today, later, waiting, ideas

    public var displayTitle: String {
        switch self {
        case .inbox: return "Inbox"
        case .today: return "Today"
        case .later: return "Later"
        case .waiting: return "Waiting"
        case .ideas: return "Ideas"
        }
    }
}

public enum TileSourceKind: String, Codable, Equatable, Sendable {
    case proposal, question, task, waiting, candidate, note, capture
}

public enum TileActionKind: String, CaseIterable, Equatable, Sendable {
    case approve, reject, delete, deferItem

    public var label: String {
        switch self {
        case .approve: return "Approve"
        case .reject: return "Reject"
        case .delete: return "Delete"
        case .deferItem: return "Defer"
        }
    }

    public var symbol: String {
        switch self {
        case .approve: return "checkmark"
        case .reject: return "xmark"
        case .delete: return "trash"
        case .deferItem: return "clock"
        }
    }
}

public enum TileContextAction: String, CaseIterable, Equatable, Sendable {
    case change, goodFraming, badFraming
}

public struct TileCommandSpec: Equatable, Sendable {
    public var commandType: String?
    public var args: [String: JSONValue]
    public var targetBucket: TileBucket?
    public var resultingMeta: String?

    public init(commandType: String? = nil, args: [String: JSONValue] = [:], targetBucket: TileBucket? = nil, resultingMeta: String? = nil) {
        self.commandType = commandType
        self.args = args
        self.targetBucket = targetBucket
        self.resultingMeta = resultingMeta
    }
}

/// Tracks local bucket deferrals (e.g. non-task items or immediate UI feedback) until snapshot refresh.
@MainActor @Observable
public final class TileDeferralStore {
    public static let shared = TileDeferralStore()
    public private(set) var deferredHandles: Set<String> = []

    public init() {}

    public func markDeferred(_ handle: String) {
        deferredHandles.insert(handle)
    }

    public func isDeferred(_ handle: String) -> Bool {
        deferredHandles.contains(handle)
    }
}

/// Unified tile presentation across Inbox, Tasks (Today/Later/Waiting/Ideas), and Search.
public struct UniversalTaskTile: Equatable, Identifiable, Sendable {
    public var id: String
    public var bucket: TileBucket
    public var sourceKind: TileSourceKind
    public var rev: String?
    public var tagLabel: String
    public var focusLabel: String?
    public var title: String
    public var metaLine: String
    public var attachmentName: String?
    public var framingSignal: FramingSignal?
    public var badgeColor: TokenColor
    public var textLineLimit: Int?
    public var isEnabled: Bool
    public var disabledReason: String?
    public var isPending: Bool
    public var isStruck: Bool
    public var overdueMark: String?
    public var sourceCaptureId: String?
    public var detailsText: String?
    /// True while the tile shows all of its text; it keeps the clamped preview otherwise.
    public var isExpanded = false
    /// True when the underlying task carries a horizon; an idea tile never does.
    public var horizonIsSet = false

    public static let swipeRightAction: TileActionKind = .approve
    public static let swipeLeftAction: TileActionKind = .reject
    public static let contextMenuActions: [TileContextAction] = [.change, .goodFraming, .badFraming]
    /// The More control's label, shared with the views and the acceptance surface.
    public static let moreMenuAccessibleName = "More actions"
    /// Every action the tile offers, in the order the row shows them.
    public var actionLabels: [String] { TileActionKind.allCases.map(\.label) }
    /// The untruncated stored text.
    public var fullText: String { title }
    /// The preview clamp: three lines, or nil where the layout wraps the whole text.
    public var collapsedLineLimit: Int? { textLineLimit }
    /// Nil while expanded, so the whole text shows.
    public var resolvedTextLineLimit: Int? { isExpanded ? nil : collapsedLineLimit }

    public func withExpansion(_ expanded: Bool) -> UniversalTaskTile {
        var copy = self
        copy.isExpanded = expanded
        return copy
    }

    public init(id: String, bucket: TileBucket, sourceKind: TileSourceKind, title: String) {
        self.id = id
        self.bucket = bucket
        self.sourceKind = sourceKind
        self.rev = nil
        self.tagLabel = bucket.displayTitle
        self.focusLabel = nil
        self.title = title
        self.metaLine = ""
        self.attachmentName = nil
        self.framingSignal = nil
        self.badgeColor = Self.defaultColor(for: bucket)
        self.textLineLimit = 3
        self.isEnabled = true
        self.disabledReason = nil
        self.isPending = false
        self.isStruck = false
        self.overdueMark = nil
        self.sourceCaptureId = nil
        self.detailsText = nil
    }

    public static func defaultColor(for bucket: TileBucket) -> TokenColor {
        switch bucket {
        case .inbox, .ideas: return DesignTokens.glowBlue
        case .today: return DesignTokens.glowAmber
        case .later: return DesignTokens.glowPurple
        case .waiting: return DesignTokens.glowCyan
        }
    }

    public static func commandSpec(for action: TileActionKind, sourceKind: TileSourceKind) -> TileCommandSpec {
        switch action {
        case .approve: return approveSpec(sourceKind)
        case .reject: return rejectSpec(sourceKind)
        case .delete: return deleteSpec(sourceKind)
        case .deferItem: return deferSpec(sourceKind)
        }
    }

    private static func approveSpec(_ kind: TileSourceKind) -> TileCommandSpec {
        switch kind {
        case .proposal: return TileCommandSpec(commandType: "proposal.approve")
        case .task: return TileCommandSpec(commandType: "task.done")
        case .waiting: return TileCommandSpec(commandType: "waiting.close")
        case .candidate: return TileCommandSpec(commandType: "candidate.promote")
        case .note, .capture, .question: return TileCommandSpec(resultingMeta: "Confirmed")
        }
    }

    private static func rejectSpec(_ kind: TileSourceKind) -> TileCommandSpec {
        switch kind {
        case .proposal: return TileCommandSpec(commandType: "proposal.reject")
        case .task: return TileCommandSpec(commandType: "task.drop")
        case .candidate: return TileCommandSpec(commandType: "candidate.drop")
        case .waiting: return TileCommandSpec(commandType: "waiting.close")
        case .note: return TileCommandSpec(commandType: "item.remove")
        case .capture, .question: return TileCommandSpec(resultingMeta: "Dismissed")
        }
    }

    private static func deleteSpec(_ kind: TileSourceKind) -> TileCommandSpec {
        switch kind {
        case .proposal: return TileCommandSpec(commandType: "proposal.drop")
        case .task: return TileCommandSpec(commandType: "task.drop")
        case .candidate: return TileCommandSpec(commandType: "candidate.drop")
        case .waiting: return TileCommandSpec(commandType: "waiting.close")
        case .note: return TileCommandSpec(commandType: "item.remove")
        case .capture, .question: return TileCommandSpec(resultingMeta: "Removed")
        }
    }

    private static func deferSpec(_ kind: TileSourceKind) -> TileCommandSpec {
        let laterWhen: JSONValue = .object(["kind": .string("later"), "date": .null])
        if kind == .task {
            return TileCommandSpec(
                commandType: "task.defer", args: ["when": laterWhen],
                targetBucket: .later, resultingMeta: "Deferred to Later")
        }
        return TileCommandSpec(targetBucket: .later, resultingMeta: "Deferred to Later")
    }
}

/// Shared context passed into tile builders so every helper stays <= 4 parameters.
@MainActor
public struct TileBuildContext {
    public let inbox: InboxModel
    public let decisions: DecisionModel
    public let framingStore: FramingSignalStore?
    public let deferrals: TileDeferralStore?
    /// The pending moves, set after the init so the shared init keeps its four parameters.
    public var moves: TileMoveStore?
    public var textLineLimit: Int?

    public init(inbox: InboxModel, decisions: DecisionModel, framingStore: FramingSignalStore? = nil, deferrals: TileDeferralStore? = nil) {
        self.inbox = inbox
        self.decisions = decisions
        self.framingStore = framingStore
        self.deferrals = deferrals
        self.textLineLimit = 3
    }

    public func withLineLimit(_ limit: Int?) -> TileBuildContext {
        var copy = self
        copy.textLineLimit = limit
        return copy
    }
}

public extension UniversalTaskTile {
    @MainActor
    static func execute(_ action: TileActionKind, on tile: UniversalTaskTile, context: TileBuildContext) async {
        let spec = commandSpec(for: action, sourceKind: tile.sourceKind)
        if spec.targetBucket == .later { context.deferrals?.markDeferred(tile.id) }
        guard let commandType = spec.commandType else { return }
        let rev = tile.rev ?? lookupRev(handle: tile.id, in: context.inbox.snapshot)
        guard let rev, !rev.isEmpty else { return }
        context.decisions.resetState(tile.id)
        await context.decisions.send(commandType, handle: tile.id, rev: rev, args: spec.args)
    }

    @MainActor
    static func submitChange(handle: String, sourceKind: TileSourceKind, text: String, context: TileBuildContext) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let rev = lookupRev(handle: handle, in: context.inbox.snapshot), !rev.isEmpty else { return }
        let commandType = sourceKind == .proposal ? "proposal.change" : "item.correct"
        context.decisions.resetState(handle)
        await context.decisions.send(commandType, handle: handle, rev: rev, args: ["text": .string(trimmed)])
    }

    static func lookupRev(handle: String, in snapshot: Snapshot?) -> String? {
        guard let snapshot else { return nil }
        return snapshot.proposals.first { $0.handle == handle }?.rev
            ?? snapshot.tasks.first { $0.handle == handle }?.rev
            ?? snapshot.waiting.first { $0.handle == handle }?.rev
            ?? snapshot.candidates.first { $0.handle == handle }?.rev
            ?? snapshot.notes.first { $0.handle == handle }?.rev
            ?? snapshot.questions.first { $0.handle == handle }?.rev
    }

    static func extractFocusLabel(from note: String?) -> String? {
        guard let note, let start = note.firstIndex(of: "[") else { return nil }
        let after = note.index(after: start)
        guard let end = note[after...].firstIndex(of: "]") else { return nil }
        let value = note[after..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 24, value.lowercased() != "x" else { return nil }
        return value
    }
}
