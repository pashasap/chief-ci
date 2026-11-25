import Foundation

public enum AppTab: Equatable, Hashable, Sendable {
    case home, inbox, today, settings
}

public extension AppTab {
    /// Legacy alias while Wave 2 migrates BriefView from a root tab to a Home sub-route.
    static var brief: AppTab { .home }
}

public enum AppRoute: Equatable, Hashable, Sendable {
    case tab(AppTab)
    case brief
    case search
}

public enum AppAction: Equatable, Sendable {
    case startRecording
    /// Carries the full link text.
    case pair(String)
    case openTab(AppTab)
    case openRoute(AppRoute)
}

/// Maps incoming links and notifications to app actions.
public struct AppRouter: Sendable {
    public static let tabs: [AppTab] = [.home, .inbox, .today, .settings]

    public init() {}

    public func handle(url: URL) -> AppAction? {
        guard url.scheme?.lowercased() == "chief" else { return nil }
        switch url.host?.lowercased() {
        case "capture": return .startRecording
        case "pair": return .pair(url.absoluteString)
        default: return nil
        }
    }

    public func handle(notificationIdentifier: String) -> AppAction? {
        if notificationIdentifier == NotificationIdentifier.briefReminder {
            return .openRoute(.brief)
        }
        return NotificationRouter().destination(for: notificationIdentifier).map { .openTab($0) }
    }

    /// An app launch without a link does nothing, so it never starts a recording.
    public func launch(url: URL?) -> AppAction? {
        guard let url else { return nil }
        return handle(url: url)
    }
}
