import SwiftUI
import Core

/// Renders the Core `ShareControls`: 'Share' (text) and 'Share as file' (temporary .md file). No logic here.
struct ShareButtons: View {
    @State private var controls: ShareControls
    @State private var failed = false

    init(make: (any FileStore) -> ShareControls) {
        _controls = State(initialValue: make(DirectoryFileStore(folder: ShareFolder.url)))
    }

    var body: some View {
        HStack(spacing: 16) {
            if let text = controls.share.text, controls.share.isEnabled {
                ShareLink(item: text) { Text(controls.share.label) }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel(controls.share.label)
            } else {
                disabled(controls.share)
            }
            if let url = controls.fileURL, controls.shareAsFile.isEnabled {
                ShareLink(item: url) { Text(controls.shareAsFile.label) }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel(controls.shareAsFile.label)
            } else {
                disabled(controls.shareAsFile)
            }
        }
        .task {
            do { try controls.prepareFile() } catch { failed = true }
        }
        if failed { Text("Could not prepare the file").foregroundStyle(Theme.amber).wrapping() }
    }

    @ViewBuilder private func disabled(_ control: ShareControl) -> some View {
        VStack(alignment: .leading) {
            Button(control.label) {}
                .disabled(true)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(control.label)
            if let reason = control.disabledReason {
                Text(reason).font(.caption).foregroundStyle(Theme.secondaryText).wrapping()
            }
        }
    }
}
