import SwiftUI
import Core

/// Renders one Core `TodayIdeaRow`: its controls, the Augment field, the queued line and the Delete confirmation.
struct TodayIdeaCard: View {
    let idea: TodayIdeaRow
    @Binding var draft: String
    let run: (InboxControl) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(idea.text).wrapping()
            if let note = idea.note { Text(note).font(.footnote).foregroundStyle(Theme.secondaryText).wrapping() }
            if let queued = idea.queuedLine {
                Text(queued).font(.caption).foregroundStyle(Theme.secondaryText)
            }
            if let field = idea.textField {
                TextField(field.placeholder, text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(field.placeholder)
            }
            controls
            if let confirmation = idea.confirmation {
                Text(confirmation.message).wrapping()
                HStack(spacing: 8) {
                    ControlButton(control: confirmation.confirm) { run(confirmation.confirm) }
                    ControlButton(control: confirmation.cancel) { run(confirmation.cancel) }
                }
            }
            Text(idea.handle).font(.caption2).foregroundStyle(Theme.secondaryText)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    private var controls: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(idea.controls.enumerated()), id: \.offset) { _, control in
                    ControlButton(control: control) { run(control) }
                }
            }
        }
    }
}
