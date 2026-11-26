import SwiftUI
import Core

/// Safe-area-bounded modal sheet to create a locally persisted AI Focus lens.
struct FocusEditorSheet: View {
    let model: FocusFilterModel
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var purpose = ""

    private var canSave: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientScreenCanvas()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        labelField
                        purposeField
                        actionButtons
                    }
                    .padding(20)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("New AI Focus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.primaryWhite)
            Text("AI screens future ideas against this")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .wrapping()
        }
    }

    private var labelField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Focus Label")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            TextField("e.g. Carvolix", text: $label)
                .accessibilityLabel(FocusEditorScreen.labelFieldAccessibilityLabel)
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.text)
                .padding(14)
                .liquidGlassTile(glow: .teal)
        }
    }

    private var purposeField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Purpose")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            TextField(
                "Purpose (AI screens future ideas against this)",
                text: $purpose,
                axis: .vertical
            )
            .lineLimit(3...6)
            .accessibilityLabel(FocusEditorScreen.purposeFieldAccessibilityLabel)
            .textFieldStyle(.plain)
            .foregroundStyle(Theme.text)
            .padding(14)
            .liquidGlassTile(glow: .none)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button("Discard") { dismiss() }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, minHeight: Theme.minimumTapTarget)
                .background(Theme.primaryWhite.opacity(0.1), in: Capsule())
                .buttonStyle(.plain)

            Button("Save Focus") {
                model.addCustomFocus(label: label, purpose: purpose)
                dismiss()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.primaryWhite)
            .frame(maxWidth: .infinity, minHeight: Theme.minimumTapTarget)
            .background(
                LinearGradient(
                    colors: [Theme.glowTeal, Theme.accent],
                    startPoint: .leading, endPoint: .trailing),
                in: Capsule())
            .opacity(canSave ? 1 : 0.45)
            .disabled(!canSave)
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }
}
