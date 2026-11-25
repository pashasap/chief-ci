import SwiftUI
import Core

struct OpenedCapture: Identifiable {
    let id = UUID()
    let model: CaptureDetailModel
}

/// Renders the Core `CaptureSheetScreen` description in Obsidian Liquid Glass.
struct CaptureSheet: View {
    let model: CaptureDetailModel
    let environment: AppEnvironment
    let close: () -> Void

    var body: some View {
        let screen = CaptureSheetScreen(detail: model)
        NavigationStack {
            ZStack {
                AmbientScreenCanvas()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(screen.sections.enumerated()), id: \.offset) { index, section in
                            sectionCard(section, screen: screen, isFirst: index == 0)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(screen.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(screen.doneLabel, action: close).touchTarget().accessibilityLabel(screen.closeLabel)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func sectionCard(_ section: CaptureSheetSection, screen: CaptureSheetScreen, isFirst: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
            sectionContent(section)
            if isFirst {
                HStack(spacing: 8) {
                    Text(screen.status).font(.caption).foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Text(screen.captureId).font(.caption2).foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .liquidGlassTile(glow: isFirst ? .cyan : .blue)
    }

    @ViewBuilder
    private func sectionContent(_ section: CaptureSheetSection) -> some View {
        if let text = section.text {
            if let attachmentName = TypedCaptureModel.extractAttachmentName(from: text) {
                Label(attachmentName, systemImage: "paperclip")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.heroEnd)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.selectedTabFill.opacity(0.85), in: Capsule())
            }
            Text(text).foregroundStyle(Theme.text).lineLimit(section.lineLimit).wrapping()
        }
        if let empty = section.emptyText {
            Text(empty).foregroundStyle(Theme.secondaryText).wrapping()
        }
        ForEach(section.rows, id: \.handle) { row in
            NavigationLink {
                ItemDetailView(handle: row.handle, environment: environment, closeAfterAction: close)
            } label: {
                rowContent(row)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(row.text), \(row.handle)")
        }
    }

    private func rowContent(_ row: CaptureSheetRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label = row.label { Text(label).font(.caption).foregroundStyle(Theme.accent) }
            Text(row.text).foregroundStyle(Theme.text).lineLimit(3).wrapping()
            if let queued = row.queuedLine { Text(queued).font(.caption).foregroundStyle(Theme.secondaryText) }
            Text(row.handle).font(.caption2).foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surfaceDeep.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
