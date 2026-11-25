import SwiftUI
import UIKit
import Core

struct CaptureOrbView: View {
    let model: CaptureOrbModel
    let availability: RecordAvailability
    let onStartVoice: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false
    @State private var pulsing = false

    var body: some View {
        orbCore
            .frame(width: Theme.orbDiameter, height: Theme.orbDiameter)
            .contentShape(Circle())
            .onTapGesture { triggerTap() }
            .onLongPressGesture(minimumDuration: 0.35) { triggerLongPress() }
            .onAppear { syncMotion(reduceMotion) }
            .onChange(of: reduceMotion) { _, next in syncMotion(next) }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(availability.isEnabled ? "Capture thought" : availability.accessibilityLabel)
            .accessibilityHint(BottomBarScreen.centerOrbAccessibilityHint)
            .accessibilityAction(named: "Write Capture") {
                model.chooseRadial(.keyboard, availability: availability)
            }
            .accessibilityAction(named: "Add Attachment") {
                model.chooseRadial(.attachment, availability: availability)
            }
            .accessibilityAction(named: "Voice Capture") { triggerVoiceAction() }
    }

    private var orbCore: some View {
        ZStack {
            obsidianSphere
            auroraRibbons
            innerLuminanceRing
            glossHighlight
        }
        .clipShape(Circle())
        .overlay { specularRim }
        .background { auroraHalo.allowsHitTesting(false) }
        .opacity(availability.isEnabled ? 1.0 : 0.62)
        .scaleEffect(reduceMotion ? 1.0 : (pulsing ? 1.035 : 0.98))
        .shadow(color: Theme.glowBlue.opacity(0.45), radius: 14, x: 0, y: 6)
    }

    private var auroraHalo: some View {
        Circle()
            .fill(AngularGradient(
                colors: [
                    Theme.accent, Theme.glowPurple, Theme.roseReject,
                    Theme.glowTeal, Theme.accent,
                ],
                center: .center))
            .frame(width: Theme.orbDiameter + 14, height: Theme.orbDiameter + 14)
            .blur(radius: 10)
            .opacity(availability.isEnabled ? 0.68 : 0.28)
            .rotationEffect(.degrees(reduceMotion ? 0 : (spinning ? 360 : 0)))
    }

    private var obsidianSphere: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Theme.rookBackdropTop, Theme.glassBaseBottom, Theme.canvas],
                    center: .topLeading, startRadius: 4, endRadius: Theme.orbDiameter * 0.72))
            Circle()
                .fill(RadialGradient(
                    colors: [Theme.glowBlue.opacity(0.65), .clear],
                    center: .bottom, startRadius: 2, endRadius: Theme.orbDiameter * 0.54))
        }
    }

    private var auroraRibbons: some View {
        ZStack {
            Ellipse()
                .fill(LinearGradient(
                    colors: [Theme.accent.opacity(0.92), Theme.glowPurple.opacity(0.88)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: Theme.orbDiameter * 0.72, height: Theme.orbDiameter * 0.46)
                .offset(x: -5, y: -4)
                .blur(radius: 7)
                .blendMode(.screen)
                .rotationEffect(.degrees(reduceMotion ? 18 : (spinning ? 360 : 0)))
            Ellipse()
                .fill(LinearGradient(
                    colors: [Theme.roseReject.opacity(0.88), Theme.glowTeal.opacity(0.88)],
                    startPoint: .bottomLeading, endPoint: .topTrailing))
                .frame(width: Theme.orbDiameter * 0.68, height: Theme.orbDiameter * 0.42)
                .offset(x: 6, y: 5)
                .blur(radius: 7)
                .blendMode(.screen)
                .rotationEffect(.degrees(reduceMotion ? -24 : (spinning ? -360 : 0)))
        }
    }

    private var innerLuminanceRing: some View {
        Circle()
            .strokeBorder(Theme.rookSilverMid.opacity(0.55), lineWidth: 1.5)
            .padding(6)
            .blur(radius: 1.5)
    }

    private var glossHighlight: some View {
        Capsule()
            .fill(LinearGradient(
                colors: [Theme.primaryWhite.opacity(0.54), Theme.primaryWhite.opacity(0.04)],
                startPoint: .top, endPoint: .bottom))
            .frame(width: Theme.orbDiameter * 0.54, height: Theme.orbDiameter * 0.22)
            .offset(y: -Theme.orbDiameter * 0.25)
    }

    private var specularRim: some View {
        Circle()
            .strokeBorder(
                LinearGradient(
                    colors: [Theme.primaryWhite.opacity(0.58), Theme.primaryWhite.opacity(0.14)],
                    startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1.2)
    }

    private func syncMotion(_ reduced: Bool) {
        if reduced {
            spinning = false
            pulsing = false
            return
        }
        withAnimation(.linear(duration: 5.5).repeatForever(autoreverses: false)) { spinning = true }
        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { pulsing = true }
    }

    private func triggerTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        model.tapOrb(availability: availability)
        if model.mode == .recording { onStartVoice() }
    }

    private func triggerLongPress() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        model.longPressOrb()
    }

    private func triggerVoiceAction() {
        model.chooseRadial(.voice, availability: availability)
        if model.mode == .recording { onStartVoice() }
    }
}
