let auditStops: [(id: String, root: String)] = [
    (id: "home-bento", root: "kit.audit.home-bento"),
    (id: "home-radial-orb", root: "kit.audit.home-radial-orb"),
    (id: "keyboard-composer", root: "kit.audit.keyboard-composer"),
    (id: "inbox-universal-tiles", root: "kit.audit.inbox-universal-tiles"),
    (id: "tasks-ideas", root: "kit.audit.tasks-ideas"),
    (id: "search-results", root: "kit.audit.search-results"),
    (id: "focus-modal", root: "kit.audit.focus-modal"),
    (id: "xl-bottom-bar", root: "kit.audit.xl-bottom-bar"),
    (id: "xl-today-recording", root: "kit.audit.xl-today-recording"),
    (id: "idea-controls", root: "kit.audit.idea-controls"),
    (id: "idea-controls-xl", root: "kit.audit.idea-controls-xl"),
    (id: "independent-write", root: "kit.audit.independent-write"),
    (id: "permission-recovery", root: "kit.audit.permission-recovery"),
    (id: "recording-meter", root: "kit.audit.recording-meter"),
]

extension AuditStopsUITests {
    @MainActor func test_001_home_bento() { visit("home-bento", root: "kit.audit.home-bento") }
    @MainActor func test_002_home_radial_orb() { visit("home-radial-orb", root: "kit.audit.home-radial-orb") }
    @MainActor func test_003_keyboard_composer() { visit("keyboard-composer", root: "kit.audit.keyboard-composer") }
    @MainActor func test_004_inbox_universal_tiles() { visit("inbox-universal-tiles", root: "kit.audit.inbox-universal-tiles") }
    @MainActor func test_005_tasks_ideas() { visit("tasks-ideas", root: "kit.audit.tasks-ideas") }
    @MainActor func test_006_search_results() { visit("search-results", root: "kit.audit.search-results") }
    @MainActor func test_007_focus_modal() { visit("focus-modal", root: "kit.audit.focus-modal") }
    @MainActor func test_008_xl_bottom_bar() { visit("xl-bottom-bar", root: "kit.audit.xl-bottom-bar") }
    @MainActor func test_009_xl_today_recording() { visit("xl-today-recording", root: "kit.audit.xl-today-recording") }
    @MainActor func test_010_idea_controls() { visit("idea-controls", root: "kit.audit.idea-controls") }
    @MainActor func test_011_idea_controls_xl() { visit("idea-controls-xl", root: "kit.audit.idea-controls-xl") }
    @MainActor func test_012_independent_write() { visit("independent-write", root: "kit.audit.independent-write") }
    @MainActor func test_013_permission_recovery() { visit("permission-recovery", root: "kit.audit.permission-recovery") }
    @MainActor func test_014_recording_meter() { visit("recording-meter", root: "kit.audit.recording-meter") }
}
