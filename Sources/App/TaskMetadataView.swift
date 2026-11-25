import SwiftUI
import Core

struct TaskMetadataView: View {
    let screen: TaskMetadataScreen
    let close: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent(screen.handleLabel, value: screen.handle)
                if let revision = screen.revision { LabeledContent(screen.revisionLabel, value: revision) }
                if let capture = screen.capture { LabeledContent(screen.captureLabel, value: capture) }
                if !screen.associatedCodes.isEmpty {
                    Section(screen.codesLabel) {
                        ForEach(screen.associatedCodes, id: \.self) { code in
                            Text(code)
                        }
                    }
                }
            }
            .navigationTitle(screen.title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    ControlButton(control: screen.done, tap: close)
                }
            }
        }
    }
}
