import SwiftUI
import Core

enum GlassGlowTone: Sendable {
    case blue, teal, purple, amber, cyan, none

    var tint: Color {
        switch self {
        case .blue: return Theme.glowBlue
        case .teal: return Theme.glowTeal
        case .purple: return Theme.glowPurple
        case .amber: return Theme.glowAmber
        case .cyan: return Theme.glowCyan
        case .none: return .clear
        }
    }

    var opacity: Double {
        switch self {
        case .blue: return 0.24
        case .teal: return 0.18
        case .purple: return 0.34
        case .amber: return 0.24
        case .cyan: return 0.18
        case .none: return 0
        }
    }

    var center: UnitPoint {
        switch self {
        case .blue: return .topTrailing
        case .teal: return .topLeading
        case .purple: return .bottomTrailing
        case .amber: return .topLeading
        case .cyan: return .bottomLeading
        case .none: return .center
        }
    }
}

struct AmbientScreenCanvas: View {
    var body: some View {
        ZStack {
            Theme.canvas
            ambientOrb(color: Theme.accent, opacity: 0.12, size: 320)
                .offset(x: -130, y: -260)
            ambientOrb(color: Theme.glowPurple, opacity: 0.08, size: 280)
                .offset(x: 150, y: 20)
            ambientOrb(color: Theme.glowBlue, opacity: 0.28, size: 360)
                .offset(x: 0, y: 340)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func ambientOrb(color: Color, opacity: Double, size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(
                colors: [color.opacity(opacity), color.opacity(0)],
                center: .center, startRadius: 8, endRadius: size / 2))
            .frame(width: size, height: size)
    }
}

struct LiquidGlassTileModifier: ViewModifier {
    let glow: GlassGlowTone

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.glassTileCornerRadius, style: .continuous)
        content
            .background { tileBackground(shape: shape) }
            .overlay { tileSpecularStroke(shape: shape) }
            .clipShape(shape)
            .shadow(color: .black.opacity(0.45), radius: 15, x: 0, y: 12)
    }

    private func tileBackground(shape: RoundedRectangle) -> some View {
        shape
            .fill(LinearGradient(
                colors: [
                    Theme.glassBaseTop.opacity(0.085),
                    Theme.glassBaseMid.opacity(0.65),
                    Theme.glassBaseBottom.opacity(0.82),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .background(.ultraThinMaterial, in: shape)
            .overlay {
                if glow != .none {
                    shape.fill(RadialGradient(
                        colors: [glow.tint.opacity(glow.opacity), glow.tint.opacity(0)],
                        center: glow.center, startRadius: 6, endRadius: 220))
                }
            }
    }

    private func tileSpecularStroke(shape: RoundedRectangle) -> some View {
        shape.strokeBorder(
            LinearGradient(
                colors: [Theme.primaryWhite.opacity(0.24), Theme.primaryWhite.opacity(0.05)],
                startPoint: .topLeading, endPoint: .bottomTrailing),
            lineWidth: 1)
    }
}

struct LiquidGlassCircleModifier: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        content
            .background { circleBackground }
            .overlay { circleStroke }
            .clipShape(Circle())
            .shadow(color: tint.opacity(0.26), radius: 12, x: 0, y: 6)
    }

    private var circleBackground: some View {
        Circle()
            .fill(RadialGradient(
                colors: [tint.opacity(0.28), Theme.glassBaseBottom.opacity(0.82)],
                center: .topLeading, startRadius: 4, endRadius: 48))
            .background(.ultraThinMaterial, in: Circle())
    }

    private var circleStroke: some View {
        Circle().strokeBorder(
            LinearGradient(
                colors: [Theme.primaryWhite.opacity(0.32), Theme.primaryWhite.opacity(0.07)],
                startPoint: .topLeading, endPoint: .bottomTrailing),
            lineWidth: 1)
    }
}

extension View {
    func liquidGlassTile(glow: GlassGlowTone = .none) -> some View {
        modifier(LiquidGlassTileModifier(glow: glow))
    }

    func liquidGlassCircle(tint: Color = Theme.accent) -> some View {
        modifier(LiquidGlassCircleModifier(tint: tint))
    }
}
