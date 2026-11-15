import SwiftUI
import Core

/// Renders the Core `BriefScreen` description and nothing else.
struct BriefView: View {
    let environment: AppEnvironment
    @State private var sheetHandle: String?

    private var screen: BriefScreen { BriefScreen(inbox: environment.inbox) }

    var body: some View {
        let screen = screen
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !screen.updatedText.isEmpty { Text(screen.updatedText).foregroundStyle(Theme.secondaryText).wrapping() }
                    card(screen)
                    recorded(screen)
                    results(screen)
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle(screen.header)
            .refreshable { await environment.inbox.pullToRefresh() }
        }
        .sheet(isPresented: sheetOpen) {
            if let handle = sheetHandle { ResultSheetView(model: environment.resultSheet(handle: handle)) }
        }
    }

    private var sheetOpen: Binding<Bool> {
        Binding(get: { sheetHandle != nil }, set: { if !$0 { sheetHandle = nil } })
    }

    private func card(_ screen: BriefScreen) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(screen.card.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline) {
                    Text(line.label).font(.caption).foregroundStyle(Theme.secondaryText)
                    Text(line.value).foregroundStyle(line.isWarning ? Theme.amber : Theme.text).wrapping()
                }
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    private func recorded(_ screen: BriefScreen) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(screen.recordedTitle).font(.headline).foregroundStyle(Theme.text)
            if let empty = screen.recordedEmpty { Text(empty).foregroundStyle(Theme.secondaryText).wrapping() }
            ShareButtons { screen.shareControls(files: $0) }.id(screen.recorded.count)
            ForEach(Array(screen.recorded.enumerated()), id: \.offset) { _, line in
                switch line {
                case .heading(let text): Text(text).font(.subheadline.bold()).foregroundStyle(Theme.text).wrapping()
                case .listRow(let text): Text(text).foregroundStyle(Theme.text).wrapping()
                case .gap: Spacer().frame(height: 8)
                }
            }
        }
    }

    private func results(_ screen: BriefScreen) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(screen.resultsTitle) \(screen.resultsCount)").font(.headline).foregroundStyle(Theme.text)
            ForEach(screen.results, id: \.handle) { row in
                Button { sheetHandle = row.handle } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title).foregroundStyle(Theme.text).wrapping()
                        Text(row.handle).font(.caption2).foregroundStyle(Theme.secondaryText)
                        Text(row.date).font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(row.title)
            }
        }
    }
}
