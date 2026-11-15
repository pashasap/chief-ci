import SwiftUI
import Core

/// Renders the Core `ResultSheetModel` and nothing else. Plain text blocks, no web view.
struct ResultSheetView: View {
    @State var model: ResultSheetModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.title).font(.title2.bold()).foregroundStyle(Theme.text).wrapping()
                Text(model.handle).font(.caption2).foregroundStyle(Theme.secondaryText)
                Text(model.date).font(.caption).foregroundStyle(Theme.secondaryText)
                Text(model.askedLabel).font(.headline).foregroundStyle(Theme.text)
                Text(model.asked).foregroundStyle(Theme.text).wrapping()
                if model.result.state == .loaded {
                    blocks(model.result.blocks)
                } else {
                    Text(model.shortAnswer).foregroundStyle(Theme.text).wrapping()
                }
                failure(model.result) { await model.retryResult() }
                ShareButtons { model.resultShare(files: $0) }.id(model.result.markdown)
                draft
            }
            .padding(16)
        }
        .background(Theme.background)
        .task { await model.loadResult() }
        .navigationTitle(model.sheetTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(model.doneLabel) { dismiss() }.touchTarget() } }
        }
    }

    @ViewBuilder private var draft: some View {
        if let label = model.openDraftLabel {
            if model.draft.state == .idle {
                Button(label) { Task { await model.openDraft() } }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel(label)
            }
            blocks(model.draft.blocks)
            if model.draft.state == .loaded {
                ShareButtons { model.draftShare(files: $0) }.id(model.draft.markdown)
            }
            failure(model.draft) { await model.retryDraft() }
        }
    }

    private func blocks(_ blocks: [MarkdownBlock]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let text): Text(text).font(.headline).foregroundStyle(Theme.text).wrapping()
                case .listItem(let text): Text("• " + text).foregroundStyle(Theme.text).wrapping()
                case .paragraph(let text): Text(text).foregroundStyle(Theme.text).wrapping()
                }
            }
        }
    }

    @ViewBuilder private func failure(_ section: DocSection, retry: @escaping () async -> Void) -> some View {
        if let error = section.error {
            Text(error).foregroundStyle(Theme.amber).wrapping()
            if let label = section.retryLabel {
                Button(label) { Task { await retry() } }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel(label)
            }
        }
    }
}
