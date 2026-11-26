import Foundation

public enum BottomBarKind: Equatable, Sendable {
    case home, inbox, record, tasks, settings, write
    public static var today: BottomBarKind { .tasks }
    public static var brief: BottomBarKind { .home }
}

/// Why a new recording cannot start right now. Only the recorder's own steps and a failed save hold it.
public enum RecordUnavailableReason: Equatable, Sendable {
    case starting
    case recording
    case finishing
    case storage

    public var text: String {
        switch self {
        case .starting: return "Starting a recording"
        case .recording: return "Recording"
        case .finishing: return "Saving the last recording"
        case .storage: return "Storage is unavailable"
        }
    }

    /// The spoken name of the disabled Record control, e.g. "Record unavailable: Recording".
    public var accessibilityLabel: String { "Record unavailable: " + text }
}

public struct RecordAvailability: Equatable, Sendable {
    /// nil exactly when a new recording may start; otherwise the real reason it may not.
    public let reason: RecordUnavailableReason?
    public var isEnabled: Bool { reason == nil }
    public var accessibilityRole: String { "button" }
    public var accessibilityLabel: String { reason?.accessibilityLabel ?? "Record a capture" }
    public var tint: TokenColor { isEnabled ? DesignTokens.recordRed : DesignTokens.secondaryText }

    public init(reason: RecordUnavailableReason? = nil) { self.reason = reason }

    /// For callers that only know whether Record is enabled; a disabled button names storage as its fallback.
    public init(isEnabled: Bool) { reason = isEnabled ? nil : .storage }
}

/// SF Symbols approved for the bottom bar.
public enum BottomBarSymbols {
    public static let all = ["house", "envelope", "", "doc.text", "square.grid.2x2"]
    private static let write = "square.and.pencil"
    public static func symbol(_ kind: BottomBarKind) -> String {
        switch kind {
        case .home: return all[0]
        case .inbox: return all[1]
        case .record: return all[2]
        case .tasks: return all[3]
        case .settings: return all[4]
        case .write: return write
        }
    }
}

/// A plain rectangle in points, independent of any graphics framework.
public struct LayoutFrame: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }

    public func intersects(_ other: LayoutFrame) -> Bool {
        minX < other.maxX && other.minX < maxX && minY < other.maxY && other.minY < maxY
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
    public var labelMinimumScaleFactor: Double = 0.75
    public var badgeGap: Double = 4
    public var reservesBadgeSpace = false
    public var iconTopAligned = false
    public var labelWrapsMidWord = false
    /// Horizontal gap between the icon's trailing edge and the badge; 0 keeps the default overlay layout.
    public var badgeOffset: Double = 0
    public var minimumWidth: Double { max(DesignTokens.minimumTapTarget, size) }
    public var minimumHeight: Double { max(DesignTokens.minimumTapTarget, size) }
    /// The icon sits on one shared top line, centered in the target.
    public var iconFrame: LayoutFrame {
        LayoutFrame(x: (minimumWidth - BottomBarMetrics.iconSide) / 2, y: 0,
                    width: BottomBarMetrics.iconSide, height: BottomBarMetrics.iconSide)
    }
    public var badgeFrame: LayoutFrame {
        LayoutFrame(x: iconFrame.maxX + badgeOffset, y: iconFrame.minY,
                    width: BottomBarMetrics.badgeSide, height: BottomBarMetrics.badgeSide)
    }

    static func tab(_ kind: BottomBarKind, _ label: String) -> BottomBarItem {
        BottomBarItem(
            kind: kind, label: label, role: .normal, size: DesignTokens.minimumTapTarget,
            raised: false, accessibilityLabel: label)
    }
}

enum BottomBarMetrics {
    static let recordSize: Double = DesignTokens.orbDiameter
    static let writeAllowance: Double = DesignTokens.minimumTapTarget
    static let iconSide: Double = 24
    static let badgeSide: Double = 18
    /// Badge offset token at Accessibility XL: clears the icon's trailing edge.
    static let xlBadgeOffset: Double = 4

    static func usesTwoRows(width: Double, height: Double, largestText: Bool) -> Bool {
        largestText && width < 560 && height >= 380
    }

    static func preferredHeight(width: Double, height: Double, largestText: Bool) -> Double {
        if usesTwoRows(width: width, height: height, largestText: largestText) { return 164 }
        return largestText ? 104 : max(DesignTokens.compactTabHeight, recordSize + 12)
    }
}

/// The 5-slot even bottom dock: Home, Inbox, Center Orb, Tasks, Settings.
@MainActor
public struct BottomBarScreen {
    public private(set) var items: [BottomBarItem]
    public private(set) var scalableText = true
    public private(set) var wrapsWholeWords = true
    public static let centerOrbAccessibilityHint =
        "Double tap to record voice. Long press for keyboard, attachment, or voice."

    public private(set) var usesCompactSizing = false
    public private(set) var usesEqualWidthColumns = true
    private var writeLineLimit: Int? = 1

    public var rows: [[BottomBarItem]] { [items] }

    public var writeAllowance: Double { BottomBarMetrics.writeAllowance }

    public var writeButton: BottomBarItem? {
        var item = BottomBarItem.tab(.write, "Write")
        item.size = writeAllowance
        item.labelLineLimit = writeLineLimit
        item.iconTopAligned = true
        item.reservesBadgeSpace = true
        return item
    }

    /// The slots that are tabs. Record is the center orb action, not a tab.
    public var tabs: [BottomBarItem] { items.filter { $0.kind != .record } }

    public var recordButton: BottomBarItem { items[2] }

    /// How each of the four tabs looks; the selected one differs in shape, weight and trait.
    public func tabPresentations(selected: AppTab) -> [TabPresentation] {
        tabs.map { item in
            let isSelected = TabPresentation.tab(for: item.kind) == selected
            return TabPresentation(
                kind: item.kind, isSelected: isSelected,
                shape: isSelected ? .capsule : .none,
                weight: isSelected ? .semibold : .regular,
                traits: isSelected ? [.selected] : [],
                fill: isSelected ? DesignTokens.selectedTabFill : nil,
                label: isSelected ? DesignTokens.selectedTabLabel : DesignTokens.secondaryText)
        }
    }

    public func presented(in layout: RecordingPanelLayout) -> BottomBarScreen {
        var copy = self
        copy.scalableText = true
        copy.wrapsWholeWords = true
        copy.usesCompactSizing = BottomBarMetrics.usesTwoRows(
            width: layout.width, height: layout.height, largestText: layout.largestText)
        copy.usesEqualWidthColumns = !layout.largestText
        copy.writeLineLimit = 1
        copy.items = items.map { item in
            var updated = item
            if !updated.raised {
                updated.labelLineLimit = 1
                updated.labelMinimumScaleFactor = 0.75
                updated.badgeGap = 4
                updated.reservesBadgeSpace = true
                updated.iconTopAligned = true
                updated.labelWrapsMidWord = false
                if layout.largestText { updated.badgeOffset = BottomBarMetrics.xlBadgeOffset }
            }
            return updated
        }
        return copy
    }

    public init(inboxCount: Int = 0, availability: RecordAvailability = RecordAvailability()) {
        items = [
            .tab(.home, "Home"),
            Self.inboxTab(inboxCount),
            Self.recordButton(availability),
            .tab(.tasks, "Tasks"),
            .tab(.settings, "Settings"),
        ]
    }

    /// Badges all four tabs from the Core counts; the Inbox wording stays as it always was.
    public init(counts: TabCounts, availability: RecordAvailability = RecordAvailability()) {
        items = [
            Self.countedTab(.home, "Home", count: counts.home),
            Self.inboxTab(counts.inbox),
            Self.recordButton(availability),
            Self.countedTab(.tasks, "Tasks", count: counts.tasks),
            Self.countedTab(.settings, "Settings", count: counts.settings),
        ]
    }

    private static func countedTab(_ kind: BottomBarKind, _ label: String, count: Int) -> BottomBarItem {
        var item = BottomBarItem.tab(kind, label)
        item.badge = count > 0 ? String(count) : nil
        item.accessibilityLabel = "\(label), \(count)"
        return item
    }

    private static func inboxTab(_ count: Int) -> BottomBarItem {
        var inbox = BottomBarItem.tab(.inbox, "Inbox")
        guard count > 0 else { return inbox }
        inbox.badge = String(count)
        inbox.accessibilityLabel = "Inbox, \(count)" + (count == 1 ? " needs you" : " need you")
        return inbox
    }

    private static func recordButton(_ availability: RecordAvailability) -> BottomBarItem {
        var record = BottomBarItem(
            kind: .record, label: "Record", role: .destructive, size: DesignTokens.orbDiameter,
            raised: true, accessibilityLabel: availability.accessibilityLabel)
        record.isEnabled = availability.isEnabled
        record.tint = availability.tint
        return record
    }
}
