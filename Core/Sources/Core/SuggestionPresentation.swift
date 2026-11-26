import Foundation

/// Core's allow-list for decision and task-control SF Symbols.
public enum SuggestionIcon: String, Equatable, Sendable {
    case approve, reject, change, bin, more, research, pick

    public static let allSymbols = [
        "checkmark", "xmark", "pencil", "trash", "ellipsis", "magnifyingglass", "star",
    ]

    public var symbol: String {
        switch self {
        case .approve: return Self.allSymbols[0]
        case .reject: return Self.allSymbols[1]
        case .change: return Self.allSymbols[2]
        case .bin: return Self.allSymbols[3]
        case .more: return Self.allSymbols[4]
        case .research: return Self.allSymbols[5]
        case .pick: return Self.allSymbols[6]
        }
    }

    static func forAction(_ action: InboxAction) -> Self? {
        switch action {
        case .approve, .markDone: return .approve
        case .taskMore: return .more
        case .reject: return .reject
        case .openChange: return .change
        case .dropProposal, .deleteIdea, .confirmDeleteIdea: return .bin
        case .augmentIdea: return .change
        case .researchIdea: return .research
        case .pickRemove: return .pick
        default: return nil
        }
    }
}

public enum DecisionAxis: Equatable, Sendable { case horizontal }
public enum StatusPosition: Equatable, Sendable { case aboveActions, belowActions }

public struct SuggestionDecisionGroup: Equatable, Sendable {
    public var controls: [InboxControl]
    public var deleteControl: InboxControl
    public var axis: DecisionAxis = .horizontal
    public var gap: Double = 8
}
