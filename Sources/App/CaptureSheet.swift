import SwiftUI
import Core

struct OpenedCapture: Identifiable {
    let id = UUID()
    let model: CaptureDetailModel
}

/// Renders the Core `CaptureSheetScreen` description and nothing else.
struct CaptureSheet: View {
    let model: CaptureDetailModel
    let environment: AppEnvironment
    let close: () -> Void

    var body: some View {
        let screen = CaptureSheetScreen(detail: model)
        NavigationStack {
            List {
                ForEach(Array(screen.sections.enumerated()), id: \.offset) { index, section in
                    Section(section.title) {
                        sectionContent(section)
                        if index == 0 { Text(screen.captureId).font(.caption2).foregroundStyle(Theme.secondaryText) }
                        if index == 0 { Text(screen.status).font(.caption).foregroundStyle(Theme.secondaryText) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(screen.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(screen.doneLabel, action: close).touchTarget().accessibilityLabel(screen.closeLabel)
                }
            }
        }
    }

    @ViewBuilder private func sectionContent(_ section: CaptureSheetSection) -> some View {
        if let text = section.text {
            Text(text).foregroundStyle(Theme.text).lineLimit(section.lineLimit).wrapping()
        }
        if let empty = section.emptyText {
            Text(empty).foregroundStyle(Theme.secondaryText).wrapping()
        }
        ForEach(section.rows, id: \.handle) { row in
            NavigationLink {
                ItemDetailView(handle: row.handle, environment: environment, closeAfterAction: close)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    if let label = row.label { Text(label).font(.caption).foregroundStyle(Theme.accent) }
                    Text(row.text).foregroundStyle(Theme.text).lineLimit(3).wrapping()
                    if let queued = row.queuedLine { Text(queued).font(.caption).foregroundStyle(Theme.secondaryText) }
                    Text(row.handle).font(.caption2).foregroundStyle(Theme.secondaryText)
                }
            }
            .accessibilityLabel("\(row.text), \(row.handle)")
        }
    }
}
