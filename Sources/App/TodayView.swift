import SwiftUI
import Core

/// Top-level Tasks page (`Today`, `Later`, `Waiting`, `Ideas`) rendered with Obsidian Liquid Glass Universal Tiles.
struct TodayView: View {
    let environment: AppEnvironment
    let layout: RecordingPanelLayout
    let activeFocus: String?
    let onOpenChangeComposer: ((String, String) -> Void)?

    @Environment(\.dynamicTypeSize) private var textSize
    @State private var sheetHandle: String?
    @State private var editTarget: TileEditTarget?
    @State private var framingStore = FramingSignalStore.shared
    @State private var deferrals = TileDeferralStore.shared

    init(
        environment: AppEnvironment,
        layout: RecordingPanelLayout,
        activeFocus: String? = nil,
        onOpenChangeComposer: ((String, String) -> Void)? = nil
    ) {
        self.environment = environment
        self.layout = layout
        self.activeFocus = activeFocus
        self.onOpenChangeComposer = onOpenChangeComposer
    }

    private var model: TodayModel { environment.today }
    private var inbox: InboxModel { environment.inbox }
    private var screen: TodayScreen {
        TodayScreen(model: model).presented(
            in: RecordingPanelLayout(
                width: layout.width, height: layout.height, largestText: textSize.isAccessibilitySize
            ),
            focus: activeFocus,
            deferrals: deferrals
        )
    }

    var body: some View {
        let current = screen
        VStack(spacing: 0) {
            if current.usesContentHeader {
                todayContent(current)
            } else {
                todayContent(current)
                confirmations.padding(.horizontal, 16)
            }
        }
        .background(Color.clear)
        .overlay(alignment: .top) { TransientToastBanner(message: current.message) }
        .refreshable { await inbox.pullToRefresh() }
        .sheet(isPresented: sheetOpen) {
            if let handle = sheetHandle { TaskSheetView(handle: handle, environment: environment) }
        }
        .sheet(isPresented: moreOpen) { metadataSheet(current) }
        .sheet(item: $editTarget) { target in
            TileChangeComposerSheet(target: target) { text in
                Task { await current.submitTileChange(handle: target.id, sourceKind: target.sourceKind, text: text) }
            }
        }
    }

    private var confirmations: some View {
        VStack(spacing: 0) {
            ConfirmationBar(decisions: environment.decisions)
            KitLineBar { environment.uploader.kitBar }
        }
    }

    private func todayContent(_ screen: TodayScreen) -> some View {
        let segments = screen.segments
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if screen.usesContentHeader { confirmations.id("today-confirmations") }
                    tasksHeader(screen)
                    segmentSelector(segments, screen)
                    notes(screen)
                    if let selected = segments.first(where: \.isSelected) { segmentView(selected, screen) }
                }
                .padding(16)
            }
            .onChange(of: environment.decisions.actionSerial) {
                if screen.usesContentHeader, environment.decisions.actionBar != nil {
                    proxy.scrollTo("today-confirmations", anchor: .top)
                }
            }
        }
    }

    private func tasksHeader(_ screen: TodayScreen) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(screen.eyebrow)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Theme.accent)
            HStack(alignment: .firstTextBaseline) {
                Text(screen.heading)
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.text)
                    .lineLimit(screen.headerLineLimit)
                    .wrapping()
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let dateLabel = screen.dateLabel {
                    Text(dateLabel)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }

    @ViewBuilder private func metadataSheet(_ screen: TodayScreen) -> some View {
        if let metadata: TaskMetadataScreen = screen.more {
            TaskMetadataView(screen: metadata) { Task { await screen.perform(metadata.done) } }
        }
    }

    private var moreOpen: Binding<Bool> {
        Binding(get: { screen.more != nil }, set: { if !$0 { model.moreHandle = nil } })
    }

    private var sheetOpen: Binding<Bool> {
        Binding(get: { sheetHandle != nil }, set: { if !$0 { sheetHandle = nil } })
    }

    @ViewBuilder private func segmentSelector(_ segments: [TodaySegment], _ screen: TodayScreen) -> some View {
        let strip = AccessibleTodaySegments(segments: segments, label: screen.segmentLabel, select: screen.selectSegment)
        if screen.scalableText && screen.scrollsSegmentSelector {
            FittingHorizontalRow {
                ScrollView(.horizontal) { strip }
            }
        } else {
            FittingHorizontalRow { strip }
        }
    }

    @ViewBuilder private func notes(_ screen: TodayScreen) -> some View {
        if !screen.updatedText.isEmpty { Text(screen.updatedText).foregroundStyle(Theme.secondaryText).wrapping() }
        if let text = screen.notice { Text(text).foregroundStyle(Theme.amber).wrapping() }
        KitLineBar { TodayScreen(model: model).kitLine }
    }

    @ViewBuilder private func segmentView(_ segment: TodaySegment, _ screen: TodayScreen) -> some View {
        if let intro = segment.intro { Text(intro).foregroundStyle(Theme.secondaryText).wrapping() }
        let selectedIndex = model.selectedSegment
        let tiles = screen.universalTiles(for: selectedIndex, framingStore: framingStore, deferrals: deferrals)
        if selectedIndex == 0 || selectedIndex == 1 {
            let taskLookup = Dictionary(uniqueKeysWithValues: segment.tasks.map { ($0.handle, $0) })
            if tiles.isEmpty, let empty = segment.emptyText { Text(empty).foregroundStyle(Theme.secondaryText).wrapping() }
            ForEach(tiles) { tile in
                if let row = taskLookup[tile.id] {
                    taskRow(row, tile: tile, screen: screen)
                } else {
                    UniversalTaskTileView(tile: tile, callbacks: tileCallbacks(tile, screen: screen))
                }
            }
        } else {
            if tiles.isEmpty, let empty = segment.emptyText { Text(empty).foregroundStyle(Theme.secondaryText).wrapping() }
            ForEach(tiles) { tile in
                UniversalTaskTileView(tile: tile, callbacks: tileCallbacks(tile, screen: screen))
            }
        }
    }

    private func taskRow(_ row: TodayTaskRow, tile: UniversalTaskTile, screen: TodayScreen) -> some View {
        var callbacks = tileCallbacks(tile, screen: screen)
        callbacks.onTapTitle = { sheetHandle = row.handle }
        return UniversalTaskTileView(tile: tile, callbacks: callbacks) {
            Text(row.text)
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.text)
                .strikethrough(row.isStruck)
                .lineLimit(row.textLineLimit)
                .wrapping()
        }
    }

    private func tileCallbacks(_ tile: UniversalTaskTile, screen: TodayScreen) -> TileViewCallbacks {
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
}

private struct AccessibleTodaySegments: View {
    let segments: [TodaySegment]
    let label: String
    let select: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                Button { select(index) } label: {
                    Text(segment.label)
                        .font(.subheadline.weight(segment.isSelected ? .semibold : .regular))
                        .foregroundStyle(segment.isSelected ? Theme.selectedTabLabel : Theme.secondaryText)
                        .lineLimit(segment.lineLimit)
                        .fixedSize()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(minWidth: segment.minimumWidth, minHeight: segment.minimumHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    segment.isSelected ? Theme.selectedTabFill.opacity(0.9) : Theme.glassBaseMid.opacity(0.45),
                    in: Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        Theme.primaryWhite.opacity(segment.isSelected ? 0.28 : 0.10), lineWidth: 0.75))
                .accessibilityLabel(segment.accessibilityLabel)
                .accessibilityAddTraits(segment.isSelected ? .isSelected : [])
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}
