import Foundation

public enum BriefSectionKind: Equatable, Sendable { case tasks, decisions, proposals, ideas, worker, results }

public enum BriefRowKind: Equatable, Sendable { case task, decision, proposal, idea, result }

/// One row of the default Brief: always an API 2 typed entity, carrying its own ID.
public struct BriefRow: Equatable, Sendable {
    public var id: String
    public var kind: BriefRowKind
    public var text: String
    public var controls: [InboxControl] = []
    /// The full reason of a suggestion; never truncated.
    public var because: String?
    /// Plain status shared with Inbox, detail and Today.
    public var statusText: String?
    /// The ID and queued action, shown only under Details/More.
    public var detailsText: String?
    /// Nil: ideas and suggestions wrap at any text size.
    public var textLineLimit: Int? { nil }
    /// The real target of a result or a suggestion's source capture; nil when the row has none.
    public var linkTarget: String?

    public var primaryStrings: [String] {
        [text, because, statusText].compactMap { $0 } + controls.map(\.label)
    }
}

public struct BriefSection: Equatable, Sendable {
    public var kind: BriefSectionKind
    public var rows: [BriefRow]
    /// "Kit suggests" once on the proposals section.
    public var label: String? { kind == .proposals ? KitSuggestsLabel.text : nil }
    /// Worker section only: "<handle> <date>" of health.last_result.
    public var summary: String?
    /// Set exactly when the section has no rows and no summary.
    public var emptyText: String?
}

/// The raw recorded note, with the existing Share / Share as file (R-62).
public struct BriefRecordedSection: Equatable, Sendable {
    public var title = "As recorded"
    public var text: String?
    public var emptyText: String?
    var date: String

    public static let emptyNote = "No brief was recorded today."

    @MainActor
    public func shareControls(files: any FileStore) -> ShareControls {
        let content = text.map {
            ShareContent(text: $0, fileName: ShareFileName.make(title: "Brief " + date, ext: "md"))
        }
        return ShareControls(content: content, noContentReason: "No brief was recorded today", files: files)
    }
}

/// The typed default Brief. Built only from typed snapshot entities; the note is never parsed.
@MainActor
public struct BriefPresentation {
    let inbox: InboxModel
    let clock: any Clock
    /// Nil only for a read-only Brief: ideas and suggestions then show text with no controls.
    let shared: IdeaModel?
    private var layout: RecordingPanelLayout?

    public init(inbox: InboxModel, clock: any Clock, ideas: IdeaModel) {
        self.inbox = inbox
        self.clock = clock
        self.shared = ideas
    }

    public init(inbox: InboxModel, clock: any Clock) {
        self.inbox = inbox
        self.clock = clock
        self.shared = nil
    }

    public func presented(in layout: RecordingPanelLayout) -> BriefPresentation {
        var copy = self
        copy.layout = layout
        return copy
    }

    /// Runs an idea or suggestion control through the same model Today and the Inbox use.
    public func perform(_ control: InboxControl) async {
        guard let ideas = shared else { return }
        switch control.action {
        case .augmentIdea, .researchIdea, .deleteIdea, .sendCorrection: await ideas.perform(control)
        default:
            guard control.isEnabled else { return }
            let drafts = InboxDrafts(texts: inbox.drafts.texts)
            await InboxScreen(inbox: inbox, decisions: ideas.decisions, drafts: drafts)
                .perform(control.action, drafts: drafts)
        }
    }

    private var snapshot: Snapshot? { inbox.snapshot }

    public var sections: [BriefSection] {
        [tasks, decisions, proposals, ideaSection, worker, results]
    }

    public var recorded: BriefRecordedSection {
        let brief = snapshot?.brief
        let isRecorded = brief?.recorded == true
        return BriefRecordedSection(
            text: isRecorded ? brief?.lines.joined(separator: "\n") : nil,
            emptyText: isRecorded ? nil : BriefRecordedSection.emptyNote,
            date: snapshot?.today ?? "")
    }

    public var recordedDate: String? {
        guard let date = snapshot?.brief?.date, !date.isEmpty else { return nil }
        return AgeText.dayHeader(date)
    }

    public var snapshotAge: String {
        guard let fetched = inbox.fetchedAt, let snapshot else { return "" }
        return AgeText.when(fetched, now: clock.now, zone: InboxRows.timeZone(snapshot.timezone))
    }

    public var cachedLabel: String? {
        let text = inbox.lastUpdatedText
        return text.hasPrefix("Showing saved data") ? text : nil
    }

    // MARK: Sections

    private func section(
        _ kind: BriefSectionKind, _ rows: [BriefRow], empty: String, summary: String? = nil
    ) -> BriefSection {
        BriefSection(
            kind: kind, rows: rows, summary: summary,
            emptyText: rows.isEmpty && summary == nil ? empty : nil)
    }

    private var tasks: BriefSection {
        let today = snapshot?.today ?? ""
        let due = (snapshot?.tasks ?? []).filter { task in
            guard task.state == "open", let when = task.when else { return false }
            if when.kind == "today" { return true }
            guard when.kind == "due", let date = when.date else { return false }
            return date <= today
        }
        let rows = due.map { task in
            BriefRow(
                id: task.handle, kind: .task, text: TaskTileText.text(task.text),
                controls: [
                    InboxControl(
                        label: "Mark done", role: .normal, isEnabled: true, state: .idle,
                        action: .markDone(task.handle), icon: SuggestionIcon.forAction(.markDone(task.handle)),
                        accessibilityLabel: "Mark done")
                ])
        }
        return section(.tasks, rows, empty: "Nothing due today.")
    }

    private var decisions: BriefSection {
        let rows = (snapshot?.questions ?? []).filter { $0.state == "open" }.map {
            BriefRow(id: $0.handle, kind: .decision, text: $0.question)
        }
        return section(.decisions, rows, empty: "No open decisions.")
    }

    private var proposals: BriefSection {
        guard let decisions = shared?.decisions else {
            let open = (snapshot?.proposals ?? []).filter { $0.state == "open" }
            return section(.proposals, open.map { BriefRow(id: $0.handle, kind: .proposal, text: $0.would) },
                empty: "No open proposals.")
        }
        let builder = InboxRowBuilder(decisions: decisions, drafts: InboxDrafts(texts: inbox.drafts.texts))
        let known = Set((snapshot?.captures ?? []).map(\.id))
        let listed = (snapshot?.proposals ?? []).filter {
            $0.state == "open" || decisions.state(for: $0.handle) != nil || $0.queuedLine != nil
        }
        let rows = listed.map { proposal -> BriefRow in
            let shown = builder.proposalRow(proposal)
            var row = BriefRow(id: proposal.handle, kind: .proposal, text: proposal.would, controls: shown.controls)
            row.because = proposal.because
            row.statusText = shown.statusText
            row.detailsText = shown.detailsText
            row.linkTarget = proposal.capture.flatMap { known.contains($0) ? $0 : nil }
            return row
        }
        return section(.proposals, rows, empty: "No open proposals.")
    }

    private var ideaSection: BriefSection {
        guard let ideas = shared else {
            let open = (snapshot?.candidates ?? []).filter { $0.state == nil || $0.state == "open" }
            return section(.ideas, open.map { BriefRow(id: $0.handle, kind: .idea, text: $0.text) }, empty: "No ideas yet.")
        }
        let rows = ideas.rows.map { idea -> BriefRow in
            var row = BriefRow(id: idea.handle, kind: .idea, text: idea.text, controls: idea.controls)
            row.statusText = idea.statusText
            row.detailsText = idea.detailsText
            return row
        }
        return section(.ideas, rows, empty: "No ideas yet.")
    }

    private var worker: BriefSection {
        let last = snapshot?.health?.lastResult
        let summary = last.map { [$0.handle, $0.date].compactMap { $0 }.joined(separator: " ") }
        return section(.worker, [], empty: "The worker has not reported yet.", summary: summary)
    }

    private var results: BriefSection {
        let sorted = (snapshot?.results ?? []).sorted {
            let (a, b) = ($0.date ?? "", $1.date ?? "")
            return a != b ? a > b : ($0.title ?? $0.handle) < ($1.title ?? $1.handle)
        }
        let rows = sorted.map {
            var row = BriefRow(id: $0.handle, kind: .result, text: $0.title ?? $0.handle)
            row.linkTarget = $0.handle
            return row
        }
        return section(.results, rows, empty: "No results yet.")
    }

    public var liveDateHeading: String {
        let zone = InboxRows.timeZone(snapshot?.timezone)
        return HomeScreen.compactDate(from: snapshot?.today, fallbackNow: clock.now, timeZone: zone)
    }

    public var executiveSummary: String {
        if let text = recorded.text, !text.isEmpty { return text }
        return recorded.emptyText ?? BriefRecordedSection.emptyNote
    }

    public func focusScreeningSignals(activeFocus: FocusFilter?, filters: [FocusFilter] = []) -> [String] {
        BriefScreen(inbox: inbox).focusScreeningSignals(for: activeFocus, allFilters: filters)
    }

    public func audioScript(activeFocus: FocusFilter? = nil) -> String {
        let zone = InboxRows.timeZone(snapshot?.timezone)
        return BriefScreen(inbox: inbox).spokenBriefScript(now: clock.now, timeZone: zone, focus: activeFocus)
    }
}
