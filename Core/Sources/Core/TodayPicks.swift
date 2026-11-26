import Foundation

/// Which horizon a pick belongs to; also the scope `pick.remove` carries.
public enum PickScope: String, Equatable, Hashable, Sendable {
    case today, later
}

/// A candidate decision the tile can send: the wire value of `candidate.decide`.
public enum CandidateChoice: String, Equatable, Hashable, Sendable {
    case start, keep, drop
}

/// The mark a picked row carries: Kit's label, the catalog's symbol and a token tint.
public struct PickMark: Equatable, Sendable {
    public var label: String
    public var systemImage: String
    public var tint: TokenColor

    public init(label: String, systemImage: String, tint: TokenColor) {
        self.label = label
        self.systemImage = systemImage
        self.tint = tint
    }
}

/// Every string and number the pick marks and candidate tiles show, so no view spells one.
public enum TodayPickStyle {
    public static let pickLabel = "Kit's pick"
    public static let notToday = "Not today"
    public static let notThisWeek = "Not this week"
    public static let start = "Start"
    public static let keep = "Keep"
    public static let drop = "Drop"
    public static let retry = "Retry"
    public static let controlSize: Double = 44
    public static let symbol = SuggestionIcon.pick.symbol
    public static let tint = DesignTokens.glowAmber

    public static func mark(for scope: PickScope) -> PickMark {
        PickMark(label: pickLabel, systemImage: symbol, tint: tint)
    }

    public static func removeLabel(for scope: PickScope) -> String {
        scope == .today ? notToday : notThisWeek
    }

    public static func controls() -> [(label: String, choice: CandidateChoice)] {
        [(start, .start), (keep, .keep), (drop, .drop)]
    }
}

/// A candidate tile in Later: Start, Keep and Drop, then Retry after a failure.
/// The text, clamp and expansion come from the universal tile the candidate builds.
public struct TodayCandidateTile: Equatable, Sendable {
    public var handle: String
    public var tile: UniversalTaskTile
    public var state: DecisionState?
    public var controls: [InboxControl] = []

    public init(handle: String, tile: UniversalTaskTile, state: DecisionState?, controls: [InboxControl] = []) {
        self.handle = handle
        self.tile = tile
        self.state = state
        self.controls = controls
    }

    /// The whole candidate text, never a shortened preview.
    public var text: String { tile.title }
    public var isExpanded: Bool { tile.isExpanded }
    /// Equal to the tile's resolved limit: three lines, or nil once expanded or at XL.
    public var textLineLimit: Int? { tile.resolvedTextLineLimit }

    /// The layout's clamp plus the screen's expansion state, applied in one step.
    public func withPresentation(lineLimit: Int?, expandedIDs: Set<String>) -> TodayCandidateTile {
        var adapted = tile
        adapted.textLineLimit = lineLimit
        var copy = self
        copy.tile = TileExpansion.tiles([adapted], expandedIDs: expandedIDs).first ?? adapted
        return copy
    }
}
