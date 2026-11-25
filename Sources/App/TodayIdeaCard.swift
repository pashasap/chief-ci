import SwiftUI
import Core

/// Delegates Idea rows to `UniversalTaskTileView` so Ideas share Approve/Reject/Delete/Defer, swipe, and framing signals.
struct TodayIdeaCard: View {
    let idea: TodayIdeaRow
    @Binding var draft: String
    let run: (InboxControl) -> Void
    var framingStore: FramingSignalStore = .shared
    var onEdit: ((UniversalTaskTile) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            UniversalTaskTileView(tile: tile, callbacks: callbacks)
            if let field = idea.textField {
                TextField(field.placeholder, text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(field.placeholder)
            }
            if let details = idea.detailsText {
                DisclosureGroup("More") {
                    Text(details).font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }

    private var tile: UniversalTaskTile {
        var item = UniversalTaskTile(id: idea.handle, bucket: .ideas, sourceKind: .candidate, title: idea.text)
        item.tagLabel = "Idea"
        item.metaLine = idea.statusText ?? idea.note ?? "Idea backlog"
        item.textLineLimit = idea.textLineLimit
        item.framingSignal = framingStore.signal(for: idea.handle)
        return item
    }

    private var callbacks: TileViewCallbacks {
        TileViewCallbacks(
            onAction: { action in
                switch action {
                case .approve:
                    if let c = idea.controls.first(where: { $0.action == .researchIdea(idea.handle) })
                        ?? idea.controls.first(where: { $0.action == .augmentIdea(idea.handle) }) { run(c) }
                case .reject, .delete:
                    if let c = idea.controls.first(where: { $0.action == .deleteIdea(idea.handle) }) { run(c) }
                case .deferItem:
                    break
                }
            },
            onEdit: { tile in
                if let onEdit { onEdit(tile) }
                else if let c = idea.controls.first(where: { $0.action == .augmentIdea(idea.handle) }) { run(c) }
            },
            onRate: { signal, rated in
                framingStore.record(signal, for: rated.id, snippet: rated.title)
            }
        )
    }
}
