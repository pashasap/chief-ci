import Foundation

public enum RootHeadingPlacement: Equatable, Sendable {
    case firstScrollItem
}

public struct RootHeading: Equatable, Sendable {
    public let title: String
    public let placement: RootHeadingPlacement
}

/// Scroll-away heading for a root tab or Home sub-route.
public struct RootHeadingPresentation: Equatable, Sendable {
    public let tab: AppTab
    public let route: AppRoute?
    public let contentRowCount: Int
    public let layout: RecordingPanelLayout?

    public init(tab: AppTab, contentRowCount: Int, layout: RecordingPanelLayout? = nil) {
        self.tab = tab
        self.route = nil
        self.contentRowCount = contentRowCount
        self.layout = layout
    }

    public init(route: AppRoute, contentRowCount: Int, layout: RecordingPanelLayout? = nil) {
        switch route {
        case .tab(let tab): self.tab = tab
        case .brief, .search: self.tab = .home
        }
        self.route = route
        self.contentRowCount = contentRowCount
        self.layout = layout
    }

    public var headings: [RootHeading] {
        let title: String
        switch route {
        case .brief: title = "Brief"
        case .search: title = "Search"
        case .tab, nil:
            switch tab {
            case .home: title = "Home"
            case .inbox: title = "Inbox"
            case .today: title = "Tasks"
            case .settings: title = "Settings"
            }
        }
        return [RootHeading(title: title, placement: .firstScrollItem)]
    }

    public var usesStickyNavigationTitle: Bool { false }
    public var showsBrandStrip: Bool { false }
    public var showsStatusStrip: Bool { false }
    public var usesNestedScroll: Bool { false }
    public var spacerRowCount: Int { 0 }
    public var fillerRowCount: Int { 0 }
    /// nil = unbounded, so the heading never truncates at Accessibility XL.
    public var headingLineLimit: Int? { nil }
    public var keepsPullToRefresh: Bool { true }
    public var keepsBottomComposer: Bool { true }
}
