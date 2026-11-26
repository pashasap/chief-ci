public enum AuditTextSize: Hashable, Sendable { case standard, accessibilityXL }

/// Where an audit stop launches: tab, Tasks segment, overlays and capture state.
public struct AuditDestination: Hashable, Sendable {
    public var tab: AppTab
    public var tasksSegment: Int?
    public var showsSearch = false
    public var showsFocusEditor = false
    public var showsChat = false
    public var showsIdeaControls = false
    /// The picks audit stops open a segment that always lists marked picks or candidates.
    public var showsPicks = false
    public var showsCandidates = false
    public var orbMode: String?
    public var recordingState: String?
    public var textSize: AuditTextSize = .standard
    public var seedIdeaText: String?

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
            "tasks-today-picks": "tasks-today-picks", "tasks-later-candidate": "tasks-later-candidate",
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
        case "tasks-today-picks": return make(.today) { $0.tasksSegment = 0; $0.showsPicks = true }
        case "tasks-later": return make(.today) { $0.tasksSegment = 1 }
        case "tasks-later-candidate": return make(.today) { $0.tasksSegment = 1; $0.showsCandidates = true }
        case "tasks-waiting": return make(.today) { $0.tasksSegment = 2 }
        case "tasks-ideas": return ideas("Start a seed swap at the library")
        case "idea-controls": return ideas("Make a map of neighborhood water fountains", showsControls: true)
        case "idea-controls-xl":
            return ideas(
                "Record a walking tour that explains how the old railway became a neighborhood greenway",
                showsControls: true, textSize: .accessibilityXL)
        case "focus-modal": return make(.today) { $0.showsFocusEditor = true }
        case "xl-today-recording":
            return make(.today) { $0.recordingState = "recording"; $0.textSize = .accessibilityXL }
        case "settings": return AuditDestination(tab: .settings)
        default: return nil
        }
    }

    private static func ideas(
        _ seed: String, showsControls: Bool = false, textSize: AuditTextSize = .standard
    ) -> AuditDestination {
        make(.today) {
            $0.tasksSegment = 3
            $0.seedIdeaText = seed
            $0.showsIdeaControls = showsControls
            $0.textSize = textSize
        }
    }

    private static func make(_ tab: AppTab, _ edit: (inout AuditDestination) -> Void) -> AuditDestination {
        var destination = AuditDestination(tab: tab)
        edit(&destination)
        return destination
    }
}
