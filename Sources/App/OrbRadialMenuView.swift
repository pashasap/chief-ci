import SwiftUI
import UIKit
import Core

struct OrbRadialMenuView: View {
    let model: CaptureOrbModel
    let availability: RecordAvailability
    let onVoiceSelected: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fannedOut = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if model.mode == .radialOpen {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { model.dismiss() }
                    .accessibilityHidden(true)

                ZStack {
                    ForEach(model.radialOptions, id: \.self) { option in
                        radialButton(for: option)
                            .offset(fannedOut || reduceMotion ? targetOffset(for: option) : .zero)
                            .scaleEffect(fannedOut || reduceMotion ? 1.0 : 0.45)
                            .opacity(fannedOut || reduceMotion ? 1.0 : 0.0)
                    }
                }
                .padding(.bottom, Theme.orbDiameter * 0.5)
                .onAppear { animateFan(open: true) }
                .onDisappear { fannedOut = false }
            }
        }
    }

    private func radialButton(for option: OrbRadialOption) -> some View {
        let tint = Theme.color(option.tintToken)
        return Button {
            select(option)
        } label: {
            Image(systemName: option.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: Theme.radialCircleDiameter, height: Theme.radialCircleDiameter)
                .liquidGlassCircle(tint: tint)
                .overlay {
                    Circle().strokeBorder(tint.opacity(0.65), lineWidth: 1.2)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.accessibilityLabel)
    }

    private func targetOffset(for option: OrbRadialOption) -> CGSize {
        switch option {
        case .keyboard: return CGSize(width: -84, height: -68)
        case .attachment: return CGSize(width: 0, height: -104)
        case .voice: return CGSize(width: 84, height: -68)
        }
    }

    private func animateFan(open: Bool) {
        if reduceMotion {
            fannedOut = open
            return
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
            fannedOut = open
        }
    }

    private func select(_ option: OrbRadialOption) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        model.chooseRadial(option, availability: availability)
        if option == .voice && model.mode == .recording {
            onVoiceSelected()
        }
    }
}
