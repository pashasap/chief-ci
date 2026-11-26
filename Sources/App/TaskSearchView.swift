import SwiftUI
import Core

/// Live full-corpus task search across Inbox, Today, Later, Waiting, and Ideas.
struct TaskSearchView: View {
    let environment: AppEnvironment
    let activeFocus: String?
    let framingStore: FramingSignalStore
    let onOpenChangeComposer: ((String, String) -> Void)?

    @State private var searchModel: TaskSearchModel
    @State private var editTarget: TileEditTarget?

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
        let model = TaskSearchModel(
            inbox: environment.inbox, decisions: environment.decisions,
            today: environment.today, framingStore: framingStore)
        model.activeFocus = activeFocus
        self._searchModel = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                searchHeader
                Text(searchModel.statusCaption)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .wrapping()
                resultsList
            }
            .padding(16)
        }
        .background(Color.clear)
        .onChange(of: activeFocus) { _, newValue in
            searchModel.activeFocus = newValue
        }
        .sheet(item: $editTarget) { target in
            TileChangeComposerSheet(target: target) { text in
                Task { await searchModel.submitChange(handle: target.id, sourceKind: target.sourceKind, text: text) }
            }
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                TextField("Search tasks, ideas, waiting...", text: $searchModel.query)
                    .foregroundStyle(Theme.text)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Search tasks")
                if !searchModel.query.isEmpty {
                    Button { searchModel.query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .touchTarget()
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .liquidGlassTile(glow: .teal)

            Button("Done") {
                environment.coordinator.open(route: .tab(.home))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .touchTarget()
        }
    }

    @ViewBuilder private var resultsList: some View {
        let tiles = searchModel.results
        if tiles.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("No matching tasks")
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                Text("Try another keyword or clear the search query.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .wrapping()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .liquidGlassTile(glow: .none)
        } else {
            ForEach(tiles) { tile in
                UniversalTaskTileView(tile: tile, callbacks: callbacks(for: tile))
            }
        }
    }

    private func callbacks(for tile: UniversalTaskTile) -> TileViewCallbacks {
        TileViewCallbacks(
            onAction: { action in
                Task { await searchModel.perform(action, on: tile) }
            },
            onEdit: { edited in
                if let onOpenChangeComposer { onOpenChangeComposer(edited.id, edited.title) }
                else { editTarget = TileEditTarget(id: edited.id, sourceKind: edited.sourceKind, title: edited.title) }
            },
            onRate: { signal, rated in
                framingStore.record(signal, for: rated.id, snippet: rated.title)
            },
            onMove: { target in
                Task { await searchModel.performMove(target, on: tile) }
            },
            onToggleExpansion: { searchModel.toggleExpansion(tile.id) }
        )
    }
}
