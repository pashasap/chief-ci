import Foundation

public struct BriefCardLine: Equatable, Sendable {
    public var label: String
    public var value: String
    public var isWarning: Bool
}

public enum BriefLine: Equatable, Sendable {
    case heading(String)
    case listRow(String)
    case gap
}

public struct BriefResultRow: Equatable, Sendable {
    public var handle: String
    public var title: String
    public var date: String
}

/// Everything the Brief tab shows, as plain values. The view renders this and nothing else.
@MainActor
public struct BriefScreen {
    let inbox: InboxModel?

    public let rows: [String] = []
    public let recordedTitle = "As recorded"
    public let resultsTitle = "Results"

    public init() { inbox = nil }

    public init(inbox: InboxModel) { self.inbox = inbox }

    private var snapshot: Snapshot? { inbox?.snapshot }

    public var updatedText: String { inbox?.lastUpdatedText ?? "" }

    public var header: String {
        guard let day = snapshot?.today else { return "Brief" }
        return "Brief, " + AgeText.dayHeader(day)
    }

    public var card: [BriefCardLine] {
        guard snapshot != nil else { return [] }
        let ran = snapshot?.health?.briefRanToday == true
        return [
            BriefCardLine(
                label: "This morning", value: ran ? "Brief ran" : "No brief was recorded today",
                isWarning: !ran),
            BriefCardLine(label: "Worker", value: workerText, isWarning: false),
            BriefCardLine(label: "Queue", value: queueText, isWarning: false),
        ]
    }

    private var workerText: String {
        guard let last = snapshot?.health?.lastResult else { return "none" }
        return [last.handle, last.date].compactMap { $0 }.joined(separator: " ")
    }

    private var queueText: String {
        let actions = snapshot?.actions
        let counts = [
            ("queued", actions?.queued), ("running", actions?.running),
            ("blocked", actions?.blocked), ("failed", actions?.failed),
        ]
        let parts = counts.compactMap { name, count in
            (count ?? 0) > 0 ? "\(count ?? 0) \(name)" : nil
        }
        return parts.isEmpty ? "Empty" : parts.joined(separator: ", ")
    }

    public var recorded: [BriefLine] {
        guard let brief = snapshot?.brief, brief.recorded else { return [] }
        return brief.lines.map { line in
            if line.isEmpty { return .gap }
            return line.hasPrefix("•") ? .listRow(line) : .heading(line)
        }
    }

    public var recordedEmpty: String? {
        if snapshot == nil, let inbox { return inbox.emptyStateText }
        return snapshot?.brief?.recorded == true ? nil : "No brief was recorded today."
    }

    public var resultsCount: Int { snapshot?.results.count ?? 0 }

    public var results: [BriefResultRow] {
        let rows = (snapshot?.results ?? []).map {
            BriefResultRow(handle: $0.handle, title: $0.title ?? $0.handle, date: $0.date ?? "")
        }
        return rows.sorted { $0.date != $1.date ? $0.date > $1.date : $0.title < $1.title }
    }

    public func liveDateHeading(now: Date, timeZone: TimeZone) -> String {
        HomeScreen.compactDate(from: snapshot?.today, fallbackNow: now, timeZone: timeZone)
    }

    public var executiveFocusSummary: String {
        if let brief = snapshot?.brief, brief.recorded {
            let lines = brief.lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if !lines.isEmpty { return lines.joined(separator: "\n") }
        }
        return recordedEmpty ?? BriefRecordedSection.emptyNote
    }

    public func focusScreeningSignals(for focus: FocusFilter?, allFilters: [FocusFilter] = []) -> [String] {
        if let focus {
            let candidates = (snapshot?.candidates ?? []).filter { $0.state == nil || $0.state == "open" }
            let matched = candidates.filter { focus.matches(text: $0.text + " " + ($0.note ?? "")) }.count
            return [
                "Active lens: \(focus.label) — \(focus.purpose)",
                "\(matched) open idea(s) match \(focus.label) screening rules.",
            ]
        }
        let names = allFilters.map(\.label)
        let lensSummary = names.isEmpty ? "Factory, Personal" : names.joined(separator: ", ")
        let openIdeas = (snapshot?.candidates ?? []).filter { $0.state == nil || $0.state == "open" }.count
        let openProposals = (snapshot?.proposals ?? []).filter { $0.state == "open" }.count
        return [
            "Screening lenses ready: \(lensSummary).",
            "\(openProposals) open proposal(s) and \(openIdeas) open idea(s) available.",
        ]
    }

    public func spokenBriefScript(now: Date, timeZone: TimeZone, focus: FocusFilter? = nil) -> String {
        let heading = liveDateHeading(now: now, timeZone: timeZone)
        let focusLine = focus.map { "Active focus: \($0.label). " } ?? ""
        return "Daily Briefing for \(heading). \(focusLine)\(executiveFocusSummary)"
    }
}
