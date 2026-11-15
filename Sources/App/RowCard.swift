import SwiftUI
import Core

/// One white rounded card for an `InboxScreenRow`.
struct RowCard: View {
    let row: InboxScreenRow
    let draft: Binding<String>
    let run: (InboxAction) -> Void
    var openCapture: (() -> Void)? = nil
    var openSource: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let kicker = row.kicker { Text(kicker).font(.caption).foregroundStyle(Theme.accent) }
            if let when = row.whenText { Text(when).font(.caption).foregroundStyle(Theme.secondaryText) }
            if let handle = row.handle { Text(handle).font(.caption2).foregroundStyle(Theme.secondaryText) }
            if let openCapture {
                Button(action: openCapture) {
                    Text(row.text).foregroundStyle(Theme.text).lineLimit(row.lineLimit).wrapping()
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain).accessibilityHint(row.openCaptureLabel)
            } else {
                Text(row.text).foregroundStyle(Theme.text).lineLimit(row.lineLimit).wrapping()
            }
            if let because = row.displayedBecause {
                Text(because).font(.callout).foregroundStyle(Theme.secondaryText).lineLimit(3).wrapping()
            }
            if let openSource { Button(row.sourceLabel, action: openSource).touchTarget() }
            if let queued = row.queuedLine { Text(queued).font(.caption).foregroundStyle(Theme.secondaryText) }
            if let status = row.status { Text(status).font(.caption).foregroundStyle(Theme.secondaryText) }
            if let wait = row.waitLine { Text(wait).font(.caption).foregroundStyle(Theme.amber).wrapping() }
            ForEach(row.filedItems, id: \.handle) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label).font(.caption).foregroundStyle(Theme.accent)
                    Text(item.text).lineLimit(3).wrapping()
                    Text(item.handle).font(.caption2).foregroundStyle(Theme.secondaryText)
                }
            }
            if let more = row.moreText { Text(more).font(.caption).foregroundStyle(Theme.secondaryText) }
            if let caption = row.stateCaption {
                Text(caption).font(.caption).foregroundStyle(row.state == .confirmed ? Theme.secondaryText : Theme.amber)
            }
            if row.stacksControls { elements }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .contentShape(Rectangle())
    }

    private var elements: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(row.elements.enumerated()), id: \.offset) { _, element in
                switch element {
                case .control(let control): ControlButton(control: control) { run(control.action) }
                case .gap: Color.clear.frame(height: 16).accessibilityHidden(true)
                case .textField(let field):
                    TextField(field.placeholder, text: draft, axis: .vertical).textFieldStyle(.roundedBorder)
                        .accessibilityLabel(field.placeholder).touchTarget()
                }
            }
        }
    }
}

/// A button drawn from an `InboxControl`.
struct ControlButton: View {
    let control: InboxControl
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            Text(control.label).wrapping().frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
        .touchTarget()
        .tint(tint)
        .disabled(!control.isEnabled)
        .accessibilityLabel(control.label)
        .accessibilityHint(control.disabledReason ?? "")
    }

    private var tint: Color {
        switch control.role {
        case .primary: return Theme.accent
        case .destructive: return Theme.destructive
        case .normal: return control.state == .pending ? Theme.amber : Theme.accent
        }
    }
}
