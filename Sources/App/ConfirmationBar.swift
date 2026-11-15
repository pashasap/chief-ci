import SwiftUI
import Core

struct ConfirmationBar: View {
    let decisions: DecisionModel
    @State private var tick = 0

    var body: some View {
        let _ = tick
        Group {
            if let bar = decisions.actionBar {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bar.message).wrapping()
                    if let undo = bar.undo {
                        ControlButton(control: undo) { Task { await decisions.undoLastAction() } }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card)
            }
        }
        .task(id: decisions.actionSerial) {
            guard decisions.actionBar != nil else { return }
            do { try await Task.sleep(for: .seconds(DecisionModel.undoWindow + 0.1)) } catch { return }
            tick += 1
        }
    }
}
