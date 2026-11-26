public struct AuditStop: Sendable {
    public let id: String
    public let root: String
    public let title: String
    public let expectation: String
    public let flows: [String]
    public let defects: [String]
}

public enum AuditStops {
    public static let all: [AuditStop] = [
        AuditStop(id: "home-bento", root: "kit.audit.home-bento", title: "Home Bento Liquid Glass", expectation: "Home shows the Liquid Glass Rook, borderless live date typography, Needs Attention, Daily Briefing with Play icon, Focus rings, and 2x2 Today/Later/Waiting/Ideas grid.", flows: ["F-07"], defects: []),
        AuditStop(id: "home-radial-orb", root: "kit.audit.home-radial-orb", title: "Orb Long-Press 3-Way Radial", expectation: "Center orb long-press fans out three clean icon-only circles (Keyboard, Attachment, Voice) with zero text pills behind them.", flows: ["F-03", "F-05"], defects: []),
        AuditStop(id: "keyboard-composer", root: "kit.audit.keyboard-composer", title: "Dynamic 1-5 Line Keyboard Composer", expectation: "Dynamic composer sits cleanly within horizontal margins above the dock with optional attachment chip, Discard, and Send to Kit.", flows: ["F-05"], defects: []),
        AuditStop(id: "inbox-universal-tiles", root: "kit.audit.inbox-universal-tiles", title: "Inbox Universal Task Tiles", expectation: "Inbox renders UniversalTaskTileView cards with Approve, Reject, Delete, Defer, swipe actions, and context framing menu.", flows: ["F-07", "F-08"], defects: []),
        AuditStop(id: "tasks-today", root: "kit.audit.tasks-today", title: "Tasks Tab Today Segment", expectation: "Tasks tab on the Today segment lists today's task tiles under the dated Today header.", flows: ["F-07"], defects: []),
        AuditStop(id: "tasks-later", root: "kit.audit.tasks-later", title: "Tasks Tab Later Segment", expectation: "Tasks tab on the Later segment lists deferred task tiles grouped under the Later header.", flows: ["F-07"], defects: []),
        AuditStop(id: "tasks-waiting", root: "kit.audit.tasks-waiting", title: "Tasks Tab Waiting Segment", expectation: "Tasks tab on the Waiting segment lists items waiting on someone else under the Waiting header.", flows: ["F-07"], defects: []),
        AuditStop(id: "settings", root: "kit.audit.settings", title: "Settings", expectation: "Settings tab shows the Settings title with pairing, reminders and diagnostics sections.", flows: ["F-07"], defects: []),
        AuditStop(id: "tasks-ideas", root: "kit.audit.tasks-ideas", title: "Tasks Tab Ideas Segment", expectation: "Top-level Tasks tab titled Tasks on Ideas segment shows Idea tiles with a Make it a task control and the same universal actions and framing menu.", flows: ["F-04"], defects: []),
        AuditStop(id: "search-results", root: "kit.audit.search-results", title: "Live Task Search", expectation: "Live Search filters tasks, waiting items, and ideas across all buckets with instant action execution.", flows: ["F-07"], defects: []),
        AuditStop(id: "focus-modal", root: "kit.audit.focus-modal", title: "Add AI Focus Modal", expectation: "New AI Focus modal sheet is centered within safe area bounds with Focus Label, Purpose, Discard, and Save Focus.", flows: ["F-07"], defects: []),
        AuditStop(id: "xl-bottom-bar", root: "kit.audit.xl-bottom-bar", title: "Accessibility XL bottom bar", expectation: "At Accessibility XL the four whole tab labels have aligned icons and Inbox has a separate 1234 badge read as Inbox, 1234 need you.", flows: ["F-07"], defects: ["F-f0e98f"]),
        AuditStop(id: "xl-today-recording", root: "kit.audit.xl-today-recording", title: "Accessibility XL Today with recording", expectation: "At Accessibility XL the dated header, full titles and counted filters are reachable behind the scrollable recording panel, and the tab bar, Stop and Discard remain reachable.", flows: ["F-03", "F-04"], defects: ["F-909771"]),
        AuditStop(id: "idea-controls", root: "kit.audit.idea-controls", title: "Shared idea controls", expectation: "One idea row shows Augment, Research and Delete as separate 44 pt buttons with a plain status line and no ID outside More.", flows: ["F-04"], defects: []),
        AuditStop(id: "idea-controls-xl", root: "kit.audit.idea-controls-xl", title: "Shared idea controls at Accessibility XL", expectation: "At Accessibility XL the idea text and the Augment, Research and Delete labels wrap whole words with no truncation and each button stays at least 44 pt.", flows: ["F-04"], defects: []),
        AuditStop(id: "independent-write", root: "kit.audit.independent-write", title: "Independent Write", expectation: "The sample draft is already in What is on your mind, with Send, Cancel, Record instead and Discard draft available in the editor.", flows: ["F-05"], defects: []),
        AuditStop(id: "permission-recovery", root: "kit.audit.permission-recovery", title: "Microphone permission recovery", expectation: "Microphone not allowed is visible with a Write control and no recording in progress.", flows: ["F-03", "F-05"], defects: []),
        AuditStop(id: "recording-meter", root: "kit.audit.recording-meter", title: "Live recording meter", expectation: "The recording panel shows a timer and sampled waveform or live meter above controls for Stop, Discard and Type instead.", flows: ["F-03"], defects: []),
    ]
}
