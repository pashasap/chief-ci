import Foundation

public enum AppTab: Equatable, Hashable, Sendable {
    case inbox, today, brief, settings
}

public enum AppAction: Equatable, Sendable {
    case startRecording
    /// Carries the full link text.
    case pair(String)
    case openTab(AppTab)
}

/// Maps incoming links to actions. Only the two known links do anything.
public struct AppRouter: Sendable {
    public static let tabs: [AppTab] = [.inbox, .today, .brief, .settings]

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
        NotificationRouter().destination(for: notificationIdentifier).map { .openTab($0) }
    }

    /// An app launch without a link does nothing, so it never starts a recording.
    public func launch(url: URL?) -> AppAction? {
        guard let url else { return nil }
        return handle(url: url)
    }
}
