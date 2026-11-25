import SwiftUI
import Core

/// Horizontal scrollable AI Focus rings card with built-in/custom filters and + editor trigger.
struct FocusRingsBarView: View {
    let model: FocusFilterModel
    let onOpenEditor: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI Focus")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(model.filters) { filter in
                        focusRingButton(filter)
                    }
                    addFocusButton
                }
                .padding(.vertical, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .liquidGlassTile(glow: .none)
    }

    private func focusRingButton(_ filter: FocusFilter) -> some View {
        let isActive = model.activeFilterID == filter.id
        let tint = Theme.color(filter.tokenColor)
        return Button {
            if reduceMotion {
                model.toggleActive(id: filter.id)
            } else {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                    model.toggleActive(id: filter.id)
                }
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: filter.iconName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isActive ? Theme.primaryWhite : tint)
                    .frame(width: 42, height: 42)
                    .liquidGlassCircle(tint: tint)
                    .overlay {
                        if isActive {
                            Circle().strokeBorder(tint, lineWidth: 2)
                        }
                    }
                Text(filter.label)
                    .font(.caption2.weight(isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Theme.primaryWhite : Theme.secondaryText)
                    .lineLimit(1)
            }
            .frame(minWidth: Theme.minimumTapTarget, minHeight: Theme.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(filter.label) Focus")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .contextMenu {
            if !filter.isBuiltIn {
                Button("Remove Focus", role: .destructive) {
                    model.removeCustomFocus(id: filter.id)
                }
            }
        }
    }

    private var addFocusButton: some View {
        Button(action: onOpenEditor) {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 42, height: 42)
                    .liquidGlassCircle(tint: Theme.accent)
                Text("Add")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            .frame(minWidth: Theme.minimumTapTarget, minHeight: Theme.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add AI Focus")
    }
}
