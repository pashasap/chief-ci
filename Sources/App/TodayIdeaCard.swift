import SwiftUI
import Core

/// Renders the shared Idea controls alongside the universal tile.
struct TodayIdeaCard: View {
    let tile: UniversalTaskTileView<UniversalTileDefaultTitle>
    let idea: TodayIdeaRow
    @Binding var draft: String
    let run: (InboxControl) -> Void

    var body: some View {
        VStack(alignment: .leading) {
            tile
            if let field = idea.textField {
                TextField(field.placeholder, text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(field.placeholder)
            }
            ViewThatFits(in: .horizontal) {
                HStack { controls }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading) { controls }
            }
            if let details = idea.detailsText {
                DisclosureGroup("Details") {
                    Text(details).font(.caption).foregroundStyle(Theme.secondaryText).wrapping()
                }
            }
        }
    }

    private var controls: some View {
        ForEach(idea.controls, id: \.action) { control in
            ControlButton(control: control) { run(control) }
        }
    }
}
