import SwiftUI
import Core

/// Kit's line after the server confirmed something. `line` is read again when the line's time is up,
/// so Core's clock decides when it goes; the view only asks for a redraw.
struct KitLineBar: View {
    let line: () -> String?
    @State private var tick = 0

    var body: some View {
        let _ = tick
        let text = line()
        Group {
            if let text {
                Text(text)
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
                    .accessibilityLabel(text)
            }
        }
        .task(id: text) {
            guard text != nil else { return }
            do {
                try await Task.sleep(for: .seconds(KitVoice.barSeconds + 0.1))
            } catch {
                return
            }
            tick += 1
        }
    }
}
