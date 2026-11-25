import Foundation

public enum TabIndicatorShape: Equatable, Sendable { case capsule, none }
public enum TabLabelWeight: Equatable, Sendable { case semibold, regular }
public enum TabTrait: Equatable, Hashable, Sendable { case selected }
public enum ControlAlignment: Equatable, Sendable { case leading, center, trailing }

/// The look of one tab: colour is never the only signal of selection.
public struct TabPresentation: Equatable, Sendable {
    public var kind: BottomBarKind
    public var isSelected: Bool
    public var shape: TabIndicatorShape
    public var weight: TabLabelWeight
    public var traits: Set<TabTrait>
    public var fill: TokenColor?
    public var label: TokenColor

    static func tab(for kind: BottomBarKind) -> AppTab? {
        switch kind {
        case .home: return .home
        case .inbox: return .inbox
        case .tasks: return .today
        case .settings: return .settings
        case .record, .write: return nil
        }
    }
}
