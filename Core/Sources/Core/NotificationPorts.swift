import Foundation

public enum NotificationTrigger: Equatable, Sendable {
    /// Repeats every day at this wall-clock time.
    case daily(hour: Int, minute: Int, timeZone: TimeZone)
    /// Fires once at this moment.
    case once(Date)
}

public struct NotificationRequest: Equatable, Sendable {
    public var identifier: String
    public var title: String
    public var body: String
    public var trigger: NotificationTrigger

    public init(identifier: String, title: String, body: String, trigger: NotificationTrigger) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.trigger = trigger
    }
}

/// The platform's local notifications. The app target holds the real adapter.
public protocol NotificationCenterPort: Sendable {
    var problem: String? { get }
    func requestPermission() async -> Bool
    /// A request with an identifier already scheduled replaces it.
    func schedule(_ request: NotificationRequest) async
    func remove(identifier: String) async
}

extension NotificationCenterPort {
    public var problem: String? { nil }
}

public enum NotificationCopy {
    public static let scheduleFailed = "Could not schedule reminders"
}

public enum NotificationIdentifier {
    public static let briefReminder = "chief.reminder.brief"
    public static let signingReminder = "chief.reminder.signing"
}

/// Maps a tapped notification to the tab it opens.
public struct NotificationRouter: Sendable {
    public init() {}

    public func destination(for identifier: String) -> AppTab? {
        switch identifier {
        case NotificationIdentifier.briefReminder: return .brief
        case NotificationIdentifier.signingReminder: return .settings
        default: return nil
        }
    }
}

/// The single place a push token would be registered. The v1 contract says the app never calls
/// `PUT /v1/device/push-token`, so this registers nothing.
public struct PushTokenRegistrar: Sendable {
    private let transport: any HTTPTransport

    public init(transport: any HTTPTransport) {
        self.transport = transport
    }

    public func register(token: String?) async {
        _ = transport
        _ = token
    }
}
