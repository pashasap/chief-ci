import Foundation

/// Horizon bucket shown in the 2x2 Home Bento grid and mapped to Tasks segments.
public enum HomeHorizonBucket: Int, CaseIterable, Equatable, Hashable, Sendable {
    case today = 0
    case later = 1
    case waiting = 2
    case ideas = 3

    public var title: String {
        switch self {
        case .today: return "Today"
        case .later: return "Later"
        case .waiting: return "Waiting"
        case .ideas: return "Ideas"
        }
    }

    var tileBucket: TileBucket {
        switch self {
        case .today: return .today
        case .later: return .later
        case .waiting: return .waiting
        case .ideas: return .ideas
        }
    }
}

/// Summary tile model for one Home Bento quadrant.
public struct HomeHorizonSummary: Equatable, Identifiable, Sendable {
    public var id: HomeHorizonBucket { bucket }
    public let bucket: HomeHorizonBucket
    public let count: Int
    public let previews: [String]
    public let emptyText: String

    public var title: String { bucket.title }
}

private struct HomeScreenInputs {
    let snapshot: Snapshot?
    let activeFocus: FocusFilter?
    let corpusState: TileCorpusState
    let now: Date
    let timeZone: TimeZone
}

/// Pure Foundation presentation model for the Kit Home Bento dashboard.
public struct HomeScreen: Equatable, Sendable {
    public let greetingPrefix: String
    public let greetingName: String
    public let weekday: String
    public let dayNumber: String
    public let monthName: String
    public let compactDate: String
    public let weatherTemperature: String
    public let needsAttentionCount: Int
    public let needsAttentionSubtitle: String
    public let summaries: [HomeHorizonSummary]
    public let activeFocus: FocusFilter?
    public let briefScript: String

    public init(
        snapshot: Snapshot?,
        activeFocus: FocusFilter?,
        now: Date,
        timeZone: TimeZone = .current
    ) {
        self.init(HomeScreenInputs(
            snapshot: snapshot,
            activeFocus: activeFocus,
            corpusState: TileCorpusState(),
            now: now,
            timeZone: timeZone
        ))
    }

    @MainActor
    public init(
        inbox: InboxModel,
        focus: FocusFilterModel,
        clock: any Clock,
        timeZone: TimeZone? = nil
    ) {
        let resolvedZone = timeZone ?? InboxRows.timeZone(inbox.snapshot?.timezone)
        let state = TaskSearchModel.corpusState(
            snapshot: inbox.snapshot,
            decisions: nil,
            deferrals: TileDeferralStore.shared
        )
        self.init(HomeScreenInputs(
            snapshot: inbox.snapshot,
            activeFocus: focus.activeFilter,
            corpusState: state,
            now: clock.now,
            timeZone: resolvedZone
        ))
    }

    @MainActor
    public init(
        inbox: InboxModel,
        decisions: DecisionModel,
        focus: FocusFilterModel,
        clock: any Clock
    ) {
        let resolvedZone = InboxRows.timeZone(inbox.snapshot?.timezone)
        let state = TaskSearchModel.corpusState(
            snapshot: inbox.snapshot,
            decisions: decisions,
            deferrals: TileDeferralStore.shared
        )
        self.init(HomeScreenInputs(
            snapshot: inbox.snapshot,
            activeFocus: focus.activeFilter,
            corpusState: state,
            now: clock.now,
            timeZone: resolvedZone
        ))
    }

    private init(_ inputs: HomeScreenInputs) {
        let parts = Self.heroParts(now: inputs.now, timeZone: inputs.timeZone)
        self.greetingPrefix = parts.greetingPrefix
        self.greetingName = "Alex"
        self.weekday = parts.weekday
        self.dayNumber = parts.dayNumber
        self.monthName = parts.monthName
        self.compactDate = parts.compactDate
        self.weatherTemperature = "--°"
        self.activeFocus = inputs.activeFocus

        let attention = Self.attentionCount(
            snapshot: inputs.snapshot,
            state: inputs.corpusState,
            activeFocus: inputs.activeFocus
        )
        self.needsAttentionCount = attention
        self.needsAttentionSubtitle = Self.attentionSubtitle(count: attention)
        self.summaries = Self.buildSummaries(
            snapshot: inputs.snapshot,
            state: inputs.corpusState,
            activeFocus: inputs.activeFocus
        )
        self.briefScript = Self.buildBriefScript(
            snapshot: inputs.snapshot,
            compactDate: parts.compactDate,
            attentionCount: attention,
            activeFocus: inputs.activeFocus
        )
    }

    public func summary(for bucket: HomeHorizonBucket) -> HomeHorizonSummary {
        summaries.first { $0.bucket == bucket }
            ?? HomeHorizonSummary(bucket: bucket, count: 0, previews: [], emptyText: "None in focus")
    }

    // MARK: Hero Formatting

    static func compactDate(from iso: String?, fallbackNow: Date, timeZone: TimeZone) -> String {
        if let iso, let parsed = isoDate(iso, timeZone: timeZone) {
            return format(parsed, format: "EEEE, d MMM", timeZone: timeZone)
        }
        return format(fallbackNow, format: "EEEE, d MMM", timeZone: timeZone)
    }

    private struct HeroParts {
        let greetingPrefix: String
        let weekday: String
        let dayNumber: String
        let monthName: String
        let compactDate: String
    }

    private static func heroParts(now: Date, timeZone: TimeZone) -> HeroParts {
        let cal = AgeText.calendar(timeZone)
        let hour = cal.component(.hour, from: now)
        let prefix: String
        if hour < 12 {
            prefix = "Good Morning,"
        } else if hour < 17 {
            prefix = "Good Afternoon,"
        } else {
            prefix = "Good Evening,"
        }
        return HeroParts(
            greetingPrefix: prefix,
            weekday: format(now, format: "EEEE", timeZone: timeZone),
            dayNumber: format(now, format: "d", timeZone: timeZone),
            monthName: format(now, format: "MMMM", timeZone: timeZone),
            compactDate: format(now, format: "EEEE, d MMM", timeZone: timeZone)
        )
    }

    private static func format(_ date: Date, format: String, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private static func isoDate(_ iso: String, timeZone: TimeZone) -> Date? {
        let parts = iso.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else { return nil }
        return AgeText.calendar(timeZone).date(
            from: DateComponents(year: year, month: month, day: day, hour: 12)
        )
    }

    // MARK: Bento Filtering via Shared Corpus Tiles

    private static func attentionCount(
        snapshot: Snapshot?,
        state: TileCorpusState,
        activeFocus: FocusFilter?
    ) -> Int {
        guard let snapshot else { return 0 }
        return TaskSearchModel.attentionCount(snapshot: snapshot, state: state, focus: activeFocus)
    }

    private static func attentionSubtitle(count: Int) -> String {
        guard count > 0 else { return "Inbox clear · All actions resolved." }
        let noun = count == 1 ? "item" : "items"
        return "Awaiting your action · \(count) \(noun)."
    }

    private static func buildSummaries(
        snapshot: Snapshot?,
        state: TileCorpusState,
        activeFocus: FocusFilter?
    ) -> [HomeHorizonSummary] {
        let emptyLabel = activeFocus == nil ? "All clear" : "None in focus"
        let allTiles = snapshot.map { TaskSearchModel.corpusTiles(snapshot: $0, state: state) } ?? []
        let filtered = allTiles.filter { tile in
            guard let activeFocus else { return true }
            return TaskSearchModel.matchesFocusFilter(activeFocus, tile: tile)
        }
        return HomeHorizonBucket.allCases.map { horizon in
            let matches = filtered.filter { $0.bucket == horizon.tileBucket }
            return HomeHorizonSummary(
                bucket: horizon,
                count: matches.count,
                previews: matches.prefix(2).map(\.title),
                emptyText: emptyLabel
            )
        }
    }

    private static func buildBriefScript(
        snapshot: Snapshot?,
        compactDate: String,
        attentionCount: Int,
        activeFocus: FocusFilter?
    ) -> String {
        var parts = ["Daily Briefing for \(compactDate)."]
        if let activeFocus { parts.append("Active focus: \(activeFocus.label).") }
        if attentionCount > 0 {
            let noun = attentionCount == 1 ? "item" : "items"
            parts.append("\(attentionCount) \(noun) awaiting your action.")
        } else {
            parts.append("Your inbox is clear.")
        }
        if let brief = snapshot?.brief, brief.recorded, !brief.lines.isEmpty {
            parts.append(contentsOf: brief.lines.filter { !$0.isEmpty }.prefix(6))
        }
        return parts.joined(separator: " ")
    }
}
