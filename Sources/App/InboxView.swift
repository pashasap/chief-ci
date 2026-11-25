import SwiftUI
import Core

/// Obsidian Liquid Glass Inbox queue with Universal Task Tiles and capture history.
struct InboxView: View {
    let environment: AppEnvironment
    let activeFocus: String?
    let framingStore: FramingSignalStore
    let onOpenChangeComposer: ((String, String) -> Void)?

    @State private var opened: OpenedCapture?
    @State private var editTarget: TileEditTarget?
    @State private var deferrals = TileDeferralStore.shared

    init(
        environment: AppEnvironment,
        activeFocus: String? = nil,
        framingStore: FramingSignalStore = .shared,
        onOpenChangeComposer: ((String, String) -> Void)? = nil
    ) {
        self.environment = environment
        self.activeFocus = activeFocus
        self.framingStore = framingStore
        self.onOpenChangeComposer = onOpenChangeComposer
    }

    private var drafts: InboxDrafts { environment.inbox.drafts }
    private var screen: InboxScreen {
        InboxScreen(inbox: environment.inbox, decisions: environment.decisions, drafts: drafts)
    }

    var body: some View {
        let current = screen
        let tiles = current.universalTiles(framingStore: framingStore, deferrals: deferrals, focus: activeFocus)
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    inboxHeader(current)
                    statusNotices(current)
                    if !tiles.isEmpty { proposalTilesSection(tiles, screen: current) }
                    sectionsList(current)
                }
                .padding(16)
            }
            .background(Color.clear)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await environment.inbox.pullToRefresh() }
        }
        .sheet(item: $opened) { CaptureSheet(model: $0.model, environment: environment, close: { opened = nil }) }
        .overlay(alignment: .top) { TransientToastBanner(message: current.message) }
        .sheet(item: $editTarget) { target in
            TileChangeComposerSheet(target: target) { text in
                Task { await current.submitTileChange(handle: target.id, sourceKind: target.sourceKind, text: text) }
            }
        }
    }

    private func inboxHeader(_ screen: InboxScreen) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Chief Queue")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Theme.accent)
            HStack(alignment: .center) {
                Text(RootHeadingPresentation(tab: .inbox, contentRowCount: screen.sections.count).headings[0].title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.text)
                    .wrapping()
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(screen.waitingCount(deferrals: deferrals, focus: activeFocus)) waiting")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.selectedTabLabel)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.selectedTabFill.opacity(0.85), in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.primaryWhite.opacity(0.2), lineWidth: 0.75))
            }
            Text("Swipe right to approve · left to reject · hold for framing")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .wrapping()
        }
    }

    @ViewBuilder private func statusNotices(_ screen: InboxScreen) -> some View {
        if !screen.updatedText.isEmpty { note(screen.updatedText, Theme.secondaryText) }
        if let text = screen.uploadNotice { note(text, Theme.amber) }
        if let text = screen.infoNotice { note(text, Theme.amber) }
        if let pair = screen.pairControl { ControlButton(control: pair) { run(pair.action, screen) } }
        if let text = screen.notice { note(text, Theme.amber) }
        if let text = screen.emptyText { note(text, Theme.secondaryText) }
        KitLineBar { InboxScreen(inbox: environment.inbox, decisions: environment.decisions).kitLine }
        if let text = screen.needsYouEmptyText { note(text, Theme.secondaryText) }
        if let undo = screen.undo { ControlButton(control: undo) { run(undo.action, screen) } }
    }

    private func proposalTilesSection(_ tiles: [UniversalTaskTile], screen: InboxScreen) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Kit suggests")
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Theme.secondaryText)
                .accessibilityAddTraits(.isHeader)
            ForEach(tiles) { tile in
                UniversalTaskTileView(tile: tile, callbacks: tileCallbacks(tile, screen: screen))
            }
        }
    }

    private func sectionsList(_ screen: InboxScreen) -> some View {
        ForEach(Array(screen.sections.enumerated()), id: \.offset) { _, section in
            let rows = filteredRows(in: section)
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.headingText).font(.footnote).textCase(.uppercase).foregroundStyle(Theme.secondaryText)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        rowView(row, screen: screen)
                    }
                }
            }
        }
    }

    private func filteredRows(in section: InboxSection) -> [InboxScreenRow] {
        section.rows.filter { row in
            if row.isProposal { return false }
            if let handle = row.handle, deferrals.isDeferred(handle) { return false }
            return true
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

    private func tileCallbacks(_ tile: UniversalTaskTile, screen: InboxScreen) -> TileViewCallbacks {
        TileViewCallbacks(
            onAction: { action in
                Task { await screen.performTileAction(action, on: tile, deferrals: deferrals) }
            },
            onEdit: { edited in
                if let onOpenChangeComposer { onOpenChangeComposer(edited.id, edited.title) }
                else { editTarget = TileEditTarget(id: edited.id, sourceKind: edited.sourceKind, title: edited.title) }
            },
            onRate: { signal, rated in
                framingStore.record(signal, for: rated.id, snippet: rated.title)
            }
        )
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

    private func note(_ text: String, _ color: Color) -> some View {
        Text(text).foregroundStyle(color).wrapping()
    }
}
