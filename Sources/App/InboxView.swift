import SwiftUI
import Core

/// Renders the Core `InboxScreen` description and nothing else.
struct InboxView: View {
    let environment: AppEnvironment
    @State private var opened: OpenedCapture?
    private var drafts: InboxDrafts { environment.inbox.drafts }

    private var screen: InboxScreen { InboxScreen(inbox: environment.inbox, decisions: environment.decisions, drafts: drafts) }

    var body: some View {
        let screen = screen
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    header(screen)
                    ForEach(Array(screen.sections.enumerated()), id: \.offset) { _, section in
                        sectionView(section, screen: screen)
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle(screen.title)
            .refreshable { await environment.inbox.pullToRefresh() }
        }
        .sheet(item: $opened) { CaptureSheet(model: $0.model, environment: environment, close: { opened = nil }) }
    }

    @ViewBuilder private func header(_ screen: InboxScreen) -> some View {
        if !screen.updatedText.isEmpty { note(screen.updatedText, Theme.secondaryText) }
        if let text = screen.uploadNotice { note(text, Theme.amber) }
        if let text = screen.infoNotice { note(text, Theme.amber) }
        if let pair = screen.pairControl { ControlButton(control: pair) { run(pair.action, screen) } }
        if let text = screen.notice { note(text, Theme.amber) }
        if let text = screen.message { note(text, Theme.amber) }
        if let text = screen.emptyText { note(text, Theme.secondaryText) }
        KitLineBar { InboxScreen(inbox: environment.inbox, decisions: environment.decisions).kitLine }
        if let text = screen.needsYouEmptyText { note(text, Theme.secondaryText) }
        if let undo = screen.undo { ControlButton(control: undo) { run(undo.action, screen) } }
    }

    private func note(_ text: String, _ color: Color) -> some View {
        Text(text).foregroundStyle(color).wrapping()
    }

    private func sectionView(_ section: InboxSection, screen: InboxScreen) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.headingText).font(.footnote).textCase(.uppercase).foregroundStyle(Theme.secondaryText)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                rowView(row, screen: screen)
            }
        }
    }

    @ViewBuilder private func rowView(_ row: InboxScreenRow, screen: InboxScreen) -> some View {
        if let index = row.recentIndex, index < environment.inbox.recent.count {
            let record = environment.inbox.recent[index]
            RowCard(row: row, draft: draftBinding(row.handle), run: { run($0, screen) }, openCapture: {
                opened = OpenedCapture(model: environment.detail(for: record))
            })
        } else {
            RowCard(row: row, draft: draftBinding(row.handle), run: { run($0, screen) }, openSource: sourceOpener(row))
        }
    }

    private func sourceOpener(_ row: InboxScreenRow) -> (() -> Void)? {
        guard let id = row.sourceCaptureId, let model = environment.capture(id: id) else { return nil }
        return { opened = OpenedCapture(model: model) }
    }

    private func draftBinding(_ handle: String?) -> Binding<String> {
        Binding(
            get: { handle.flatMap { drafts.texts[$0] } ?? "" },
            set: { if let handle { environment.inbox.drafts.texts[handle] = $0 } })
    }

    private func run(_ action: InboxAction, _ screen: InboxScreen) {
        let before = drafts
        environment.inbox.drafts = before.after(action)
        Task { await screen.perform(action, drafts: before) }
    }
}
