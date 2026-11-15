import SwiftUI
import Core

/// Renders the Core `ItemDetailScreen` description and nothing else.
struct ItemDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var source: OpenedCapture?
    let handle: String
    let environment: AppEnvironment
    var closeAfterAction: (() -> Void)? = nil
    @State private var drafts = InboxDrafts()

    private var screen: ItemDetailScreen {
        let sources = ItemDetailSources(
            inbox: environment.inbox, decisions: environment.decisions, corrections: environment.corrections)
        return ItemDetailScreen.make(handle: handle, sources: sources, drafts: drafts)
    }

    var body: some View {
        let screen = screen
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let kicker = screen.kicker { Text(kicker).font(.caption).foregroundStyle(Theme.accent) }
                Text(screen.text).foregroundStyle(Theme.text).lineLimit(screen.lineLimit).wrapping()
                if let because = screen.because {
                    Text(because).font(.callout).foregroundStyle(Theme.secondaryText).wrapping()
                }
                if screen.handleIsSmall { Text(screen.handle).font(.caption2).foregroundStyle(Theme.secondaryText) }
                if let notice = screen.notice { Text(notice).foregroundStyle(Theme.amber).wrapping() }
                if let message = environment.decisions.message { Text(message).foregroundStyle(Theme.amber).wrapping() }
                if let caption = screen.stateCaption, screen.state != .confirmed {
                    Text(caption).font(.caption).foregroundStyle(Theme.amber)
                }
                KitLineBar { self.screen.kitLine }
                if let capture = screen.sourceCapture {
                    Text(capture.text).font(.callout).foregroundStyle(Theme.secondaryText).lineLimit(3).wrapping()
                    Button(screen.sourceLabel) { if let model = environment.capture(id: capture.id) { source = OpenedCapture(model: model) } }.touchTarget()
                }
                elements(screen)
                if let confirmation = screen.removeConfirmation {
                    Text(confirmation.message).wrapping()
                    ControlButton(control: confirmation.confirm) { run(confirmation.confirm, screen) }
                    ControlButton(control: confirmation.cancel) { run(confirmation.cancel, screen) }
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle(screen.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $source) { CaptureSheet(model: $0.model, environment: environment, close: { source = nil }) }
        .onChange(of: environment.decisions.actionSerial) { _, _ in if screen.shouldClose { if let closeAfterAction { closeAfterAction() } else { dismiss() } } }
    }

    private func elements(_ screen: ItemDetailScreen) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(screen.elements.enumerated()), id: \.offset) { _, element in
                switch element {
                case .control(let control): ControlButton(control: control) { run(control, screen) }
                case .gap: Color.clear.frame(height: 16).accessibilityHidden(true)
                case .textField(let field):
                    TextField(field.placeholder, text: draft, axis: .vertical).textFieldStyle(.roundedBorder)
                        .accessibilityLabel(field.placeholder)
                }
            }
        }
    }

    private var draft: Binding<String> {
        Binding(get: { drafts.texts[handle] ?? "" }, set: { drafts.texts[handle] = $0 })
    }

    private func run(_ control: InboxControl, _ screen: ItemDetailScreen) {
        let before = drafts
        drafts = before.after(control.action)
        Task { await screen.perform(control, drafts: before) }
    }
}
