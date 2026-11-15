import Foundation

public enum BottomBarKind: Equatable, Sendable { case inbox, today, record, brief, settings }

public struct BottomBarItem: Equatable, Sendable {
    public var badge: String? = nil
    public var kind: BottomBarKind
    public var label: String
    public var role: ControlRole
    public var size: Double
    public var raised: Bool
    public var accessibilityLabel: String

    static func tab(_ kind: BottomBarKind, _ label: String) -> BottomBarItem {
        BottomBarItem(
            kind: kind, label: label, role: .normal, size: 44, raised: false, accessibilityLabel: label)
    }
}

/// The bar at the bottom of the app: Inbox, Today, a raised red Record button, Brief, Settings.
@MainActor
public struct BottomBarScreen {
    public let items: [BottomBarItem]

    /// The slots that are tabs. Record is a button, not a tab.
    public var tabs: [BottomBarItem] { items.filter { $0.kind != .record } }

    public var recordButton: BottomBarItem { items[2] }

    public init(inboxCount: Int = 0) {
        var inbox = BottomBarItem.tab(.inbox, "Inbox")
        if inboxCount > 0 {
            inbox.badge = String(inboxCount)
            inbox.accessibilityLabel = "Inbox, \(inboxCount)" + (inboxCount == 1 ? " needs you" : " need you")
        }
        items = [
            inbox,
            .tab(.today, "Today"),
            BottomBarItem(
                kind: .record, label: "Record", role: .destructive, size: 72, raised: true,
                accessibilityLabel: "Record a capture"),
            .tab(.brief, "Brief"),
            .tab(.settings, "Settings"),
        ]
    }
}
