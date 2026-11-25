import Foundation

/// The states the shipped content can produce, and the audit stop that shows each one.
///
/// The kinds and screens below are read from the content tables themselves (the outbox factories, the
/// KitVoice moments, the shipped tabs and the two capture states), so a new kind or screen cannot be
/// added without the audit surface test naming the stop it needs.
public enum AuditSurface {
    /// Capture kinds the outbox itself builds.
    public static var activityKinds: [String] {
        let epoch = Date(timeIntervalSince1970: 0)
        let kinds = [
            OutboxRecord.voice(clientId: "audit", recordedAt: epoch, durationS: 0).kind,
            OutboxRecord.typed(clientId: "audit", recordedAt: epoch, text: "").kind,
        ]
        return Array(Set(kinds)).sorted()
    }

    /// Kit kinds that ship a spoken line.
    public static var kitKinds: [String] {
        KitMoment.allCases
            .filter { !KitVoice.lines(for: $0).isEmpty }
            .map { String(describing: $0) }
    }

    /// The screens the shipped tabs and capture states put on the phone.
    public static var screens: [String] {
        AppRouter.tabs.map { String(describing: $0) } + ["write", "recording"]
    }

    /// Every producible state, as the audit surface test names it.
    public static var states: [String] {
        activityKinds.map { "activity:" + $0 } + kitKinds.map { "kit:" + $0 } + screens.map { "screen:" + $0 }
    }

    /// The stop that shows each state, or nil with the reason no stop ships for it.
    public static func stopID(for state: String) -> String? {
        coverage.first { $0.state == state }?.stop
    }

    /// One entry per producible state; a state missing here has no stop and no recorded reason.
    public static let coverage: [(state: String, stop: String?)] = [
        ("activity:typed", "independent-write"),
        ("activity:voice", "recording-meter"),
        ("kit:captureReached", "xl-today-recording"),
        ("kit:taskDone", "xl-today-recording"),
        ("kit:suggestionApproved", "xl-today-recording"),
        ("kit:suggestionRejected", "xl-today-recording"),
        ("kit:changeSent", "xl-today-recording"),
        ("kit:questionAnswered", "xl-today-recording"),
        ("kit:waitingClosed", "xl-today-recording"),
        ("kit:correctionAccepted", "xl-today-recording"),
        ("screen:home", "home-bento"),
        ("screen:inbox", "inbox-universal-tiles"),
        ("screen:today", "xl-today-recording"),
        ("screen:brief", "home-bento"),
        ("screen:settings", nil),
        ("screen:write", "independent-write"),
        ("screen:recording", "recording-meter"),
    ]

    /// The reason a state ships without a stop (only the ones listed below), or nil when it is covered.
    /// Anything producible but absent from `coverage` returns nil, so a new kind or screen fails the
    /// completeness test instead of inheriting a blanket excuse.
    public static func uncoveredReason(for state: String) -> String? {
        guard stopID(for: state) == nil else { return nil }
        return exceptions[state]
    }

    /// The states that ship without a stop, each with the reason.
    public static let exceptions: [String: String] = [
        "screen:settings": "no stop ships for Settings"
    ]
}
