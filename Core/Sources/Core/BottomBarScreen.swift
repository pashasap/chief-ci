import Foundation

public enum BottomBarKind: Equatable, Sendable { case inbox, today, record, brief, settings }

public struct RecordAvailability: Equatable, Sendable {
    public let isEnabled: Bool
    public var accessibilityRole: String { "button" }
    public var accessibilityLabel: String {
        isEnabled ? "Record a capture" : "Record unavailable while the last capture is being sent"
    }
    public var tint: TokenColor { isEnabled ? DesignTokens.recordRed : DesignTokens.secondaryText }

    public init(isEnabled: Bool = true) { self.isEnabled = isEnabled }
}

/// SF Symbols approved for the bottom bar.
public enum BottomBarSymbols {
    public static let all = ["tray", "checklist", "mic.fill", "doc.text", "gearshape"]
    public static func symbol(_ kind: BottomBarKind) -> String {
        switch kind {
        case .inbox: return all[0]
        case .today: return all[1]
        case .record: return all[2]
        case .brief: return all[3]
        case .settings: return all[4]
        }
    }
}

public struct BottomBarItem: Equatable, Sendable {
    public var isEnabled = true
    public var tint = DesignTokens.recordRed
    public var symbol: String { BottomBarSymbols.symbol(kind) }
    public var badge: String? = nil
    public var kind: BottomBarKind
    public var label: String
    public var role: ControlRole
    public var size: Double
    public var raised: Bool
    public var accessibilityLabel: String
    public var labelLineLimit: Int? = 1
    public var badgeGap: Double = 4
    public var reservesBadgeSpace = false
    public var iconTopAligned = false
    public var minimumWidth: Double { max(44, size) }
    public var minimumHeight: Double { max(44, size) }

    static func tab(_ kind: BottomBarKind, _ label: String) -> BottomBarItem {
        BottomBarItem(
            kind: kind, label: label, role: .normal, size: 44, raised: false, accessibilityLabel: label)
    }
}

/// The bar at the bottom of the app: Inbox, Today, a raised red Record button, Brief, Settings.
@MainActor
public struct BottomBarScreen {
    public private(set) var items: [BottomBarItem]
    public private(set) var scalableText = true
    public private(set) var wrapsWholeWords = true
    public private(set) var usesCompactSizing = false

    /// The slots that are tabs. Record is a button, not a tab.
    public var tabs: [BottomBarItem] { items.filter { $0.kind != .record } }

    public var recordButton: BottomBarItem { items[2] }

    public func presented(in layout: RecordingPanelLayout) -> BottomBarScreen {
        var copy = self
        copy.scalableText = true
        copy.wrapsWholeWords = true
        copy.usesCompactSizing = layout.largestText
        copy.items = items.map { item in
            var updated = item
            if !updated.raised {
                updated.labelLineLimit = layout.largestText ? nil : 1
                updated.badgeGap = 4
                updated.reservesBadgeSpace = true
                updated.iconTopAligned = true
            }
            return updated
        }
        return copy
    }

    public init(inboxCount: Int = 0, availability: RecordAvailability = RecordAvailability()) {
        var inbox = BottomBarItem.tab(.inbox, "Inbox")
        if inboxCount > 0 {
            inbox.badge = String(inboxCount)
            inbox.accessibilityLabel = "Inbox, \(inboxCount)" + (inboxCount == 1 ? " needs you" : " need you")
        }
        var record = BottomBarItem(
            kind: .record, label: "Record", role: .destructive, size: 72, raised: true,
            accessibilityLabel: availability.accessibilityLabel)
        record.isEnabled = availability.isEnabled
        record.tint = availability.tint
        items = [
            inbox,
            .tab(.today, "Today"),
            record,
            .tab(.brief, "Brief"),
            .tab(.settings, "Settings"),
        ]
    }
}
