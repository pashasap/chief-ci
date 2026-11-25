import SwiftUI
import Core

struct DynamicComposerSheet: View {
    let model: TypedCaptureModel
    let availability: RecordAvailability
    let onRecordInstead: () -> Void
    let onDismiss: () -> Void

    @FocusState private var fieldFocused: Bool

    private var textBinding: Binding<String> {
        Binding(get: { model.text }, set: { model.text = $0 })
    }

    var body: some View {
        let screen = TypedCaptureScreen(model: model, text: model.text, recordAvailability: availability)
        VStack(alignment: .leading, spacing: 12) {
            headerRow(screen)
            if let chip = screen.attachmentChipText {
                attachmentChip(chip)
            }
            composerField(screen)
            if let message = screen.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.roseReject)
                    .wrapping()
            }
            footerRow(screen)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassTile(glow: .cyan)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .onAppear { fieldFocused = true }
        .onChange(of: model.isClosed) { _, closed in
            if closed { onDismiss() }
        }
    }

    private func headerRow(_ screen: TypedCaptureScreen) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.glowCyan)
                .accessibilityHidden(true)
            Text(screen.heading)
                .font(.headline)
                .foregroundStyle(Theme.text)
                .wrapping()
            Spacer()
            if availability.isEnabled && model.editingHandle == nil {
                Button {
                    onRecordInstead()
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(minWidth: Theme.minimumTapTarget, minHeight: Theme.minimumTapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Record instead")
            }
        }
    }

    private func attachmentChip(_ label: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.heroEnd)
                .lineLimit(1)
                .truncationMode(.middle)
            Button {
                model.clearAttachment()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(minWidth: 28, minHeight: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove attachment")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.selectedTabFill.opacity(0.9), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.glowCyan.opacity(0.35), lineWidth: 1))
    }

    private func composerField(_ screen: TypedCaptureScreen) -> some View {
        TextField(screen.composerPlaceholder, text: textBinding, axis: .vertical)
            .lineLimit(1...5)
            .textFieldStyle(.plain)
            .font(.body)
            .foregroundStyle(Theme.text)
            .focused($fieldFocused)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.surfaceDeep.opacity(0.65), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.primaryWhite.opacity(0.14), lineWidth: 1)
            )
            .accessibilityLabel(screen.composerPlaceholder)
    }

    private func footerRow(_ screen: TypedCaptureScreen) -> some View {
        HStack(spacing: 10) {
            ForEach(screen.footerControls, id: \.label) { control in
                footerButton(control)
            }
        }
    }

    @ViewBuilder
    private func footerButton(_ control: TypedCaptureControl) -> some View {
        let isPrimary = control.action == .save
        Button {
            perform(control.action)
        } label: {
            Text(control.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isPrimary ? Theme.primaryWhite : Theme.text)
                .wrapping()
                .frame(maxWidth: .infinity, minHeight: Theme.minimumTapTarget)
                .padding(.horizontal, 12)
                .background(footerBackground(isPrimary: isPrimary, enabled: control.isEnabled))
                .clipShape(Capsule())
                .overlay {
                    Capsule().strokeBorder(Theme.primaryWhite.opacity(isPrimary ? 0.25 : 0.16), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(!control.isEnabled)
        .opacity(control.isEnabled ? 1.0 : 0.45)
        .accessibilityLabel(control.label)
        .accessibilityHint(control.disabledReason ?? "")
    }

    private func footerBackground(isPrimary: Bool, enabled: Bool) -> some ShapeStyle {
        if isPrimary {
            return AnyShapeStyle(LinearGradient(
                colors: [Theme.glowCyan, Theme.glowBlue],
                startPoint: .leading, endPoint: .trailing))
        }
        return AnyShapeStyle(Theme.glassBaseMid.opacity(enabled ? 0.72 : 0.4))
    }

    private func perform(_ action: TypedCaptureAction) {
        switch action {
        case .save:
            _Concurrency.Task { await model.submit() }
        case .discardDraft:
            model.discardDraft()
            onDismiss()
        case .cancel:
            model.cancel()
            onDismiss()
        case .recordInstead:
            onRecordInstead()
        }
    }
}
