public enum AuditTextSize: Hashable, Sendable { case standard, accessibilityXL }

/// Where an audit stop launches: tab, Tasks segment, overlays and capture state.
public struct AuditDestination: Hashable, Sendable {
    public var tab: AppTab
    public var tasksSegment: Int?
    public var showsSearch = false
    public var showsFocusEditor = false
    public var showsChat = false
    public var showsIdeaControls = false
    public var orbMode: String?
    public var recordingState: String?
    public var textSize: AuditTextSize = .standard

    public init(tab: AppTab) { self.tab = tab }
}

public enum AuditRoute {
    /// Where an unknown stop id lands.
    public static let fallbackDestination = AuditDestination(tab: .inbox)

    /// Name of the view that carries a stop's root identifier. Idea controls share one owner.
    public static func rootOwner(for id: String) -> String? {
        let owners: [String: String] = [
            "home-bento": "home", "home-radial-orb": "radial", "keyboard-composer": "composer",
            "chat-exchange": "chat",
            "independent-write": "write", "inbox-universal-tiles": "inbox",
            "tasks-today": "tasks-today", "tasks-later": "tasks-later",
            "tasks-waiting": "tasks-waiting", "tasks-ideas": "tasks-ideas",
            "search-results": "search", "focus-modal": "focus-editor",
            "permission-recovery": "recovery", "recording-meter": "recording",
            "settings": "settings", "idea-controls": "idea-controls",
            "idea-controls-xl": "idea-controls", "xl-bottom-bar": "bottom-bar",
            "xl-today-recording": "recording-xl",
        ]
        return owners[id]
    }

    public static func destination(for id: String) -> AuditDestination? {
        switch id {
        case "home-bento": return AuditDestination(tab: .home)
        case "home-radial-orb": return make(.home) { $0.orbMode = "radial" }
        case "chat-exchange": return make(.home) { $0.showsChat = true }
        case "keyboard-composer": return make(.home) { $0.orbMode = "composer" }
        case "independent-write": return make(.home) { $0.orbMode = "write" }
        case "search-results": return make(.home) { $0.showsSearch = true }
        case "permission-recovery": return make(.home) { $0.recordingState = "permission-denied" }
        case "recording-meter": return make(.home) { $0.recordingState = "meter" }
        case "xl-bottom-bar": return make(.home) { $0.textSize = .accessibilityXL }
        default: return other(id)
        }
    }

    private static func other(_ id: String) -> AuditDestination? {
        switch id {
        case "inbox-universal-tiles": return AuditDestination(tab: .inbox)
        case "tasks-today": return make(.today) { $0.tasksSegment = 0 }
        case "tasks-later": return make(.today) { $0.tasksSegment = 1 }
        case "tasks-waiting": return make(.today) { $0.tasksSegment = 2 }
        case "tasks-ideas": return make(.today) { $0.tasksSegment = 3 }
        case "idea-controls": return make(.today) { $0.tasksSegment = 3; $0.showsIdeaControls = true }
        case "idea-controls-xl":
            return make(.today) { $0.tasksSegment = 3; $0.showsIdeaControls = true; $0.textSize = .accessibilityXL }
        case "focus-modal": return make(.today) { $0.showsFocusEditor = true }
        case "xl-today-recording":
            return make(.today) { $0.recordingState = "recording"; $0.textSize = .accessibilityXL }
        case "settings": return AuditDestination(tab: .settings)
        default: return nil
        }
    }

    private static func make(_ tab: AppTab, _ edit: (inout AuditDestination) -> Void) -> AuditDestination {
        var destination = AuditDestination(tab: tab)
        edit(&destination)
        return destination
    }
}
