import SwiftUI
import Core

/// The shared suggestion row, including the non-learning deletion beside its decisions.
struct SuggestionActions: View {
    let group: SuggestionDecisionGroup
    let run: (InboxAction) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            if group.axis == .horizontal {
                HStack(spacing: group.gap) {
                    ForEach(group.controls, id: \.action) { control in
                        ControlButton(control: control) { run(control.action) }
                    }
                    ControlButton(control: group.deleteControl) { run(group.deleteControl.action) }
                }
            }
        }
    }
}
