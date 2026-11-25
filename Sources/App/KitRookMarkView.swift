import SwiftUI
import Core

private struct RookSilhouetteShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: w * 0.25, y: h * 0.14))
        path.addLine(to: CGPoint(x: w * 0.36, y: h * 0.14))
        path.addLine(to: CGPoint(x: w * 0.36, y: h * 0.23))
        path.addLine(to: CGPoint(x: w * 0.44, y: h * 0.23))
        path.addLine(to: CGPoint(x: w * 0.44, y: h * 0.14))
        path.addLine(to: CGPoint(x: w * 0.56, y: h * 0.14))
        path.addLine(to: CGPoint(x: w * 0.56, y: h * 0.23))
        path.addLine(to: CGPoint(x: w * 0.64, y: h * 0.23))
        path.addLine(to: CGPoint(x: w * 0.64, y: h * 0.14))
        path.addLine(to: CGPoint(x: w * 0.75, y: h * 0.14))
        path.addLine(to: CGPoint(x: w * 0.75, y: h * 0.31))
        path.addQuadCurve(to: CGPoint(x: w * 0.65, y: h * 0.39), control: CGPoint(x: w * 0.73, y: h * 0.37))
        path.addQuadCurve(to: CGPoint(x: w * 0.69, y: h * 0.73), control: CGPoint(x: w * 0.61, y: h * 0.56))
        path.addLine(to: CGPoint(x: w * 0.77, y: h * 0.78))
        path.addLine(to: CGPoint(x: w * 0.77, y: h * 0.87))
        path.addLine(to: CGPoint(x: w * 0.23, y: h * 0.87))
        path.addLine(to: CGPoint(x: w * 0.23, y: h * 0.78))
        path.addLine(to: CGPoint(x: w * 0.31, y: h * 0.73))
        path.addQuadCurve(to: CGPoint(x: w * 0.35, y: h * 0.39), control: CGPoint(x: w * 0.39, y: h * 0.56))
        path.addQuadCurve(to: CGPoint(x: w * 0.25, y: h * 0.31), control: CGPoint(x: w * 0.27, y: h * 0.37))
        path.closeSubpath()
        return path
    }
}

private struct RookSpecularLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.42, y: rect.height * 0.40))
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.40, y: rect.height * 0.72),
            control: CGPoint(x: rect.width * 0.44, y: rect.height * 0.56))
        return path
    }
}

struct KitRookMarkView: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Theme.rookBackdropTop, Theme.rookBackdropBottom],
                        center: .center, startRadius: 2, endRadius: 24))
                Circle()
                    .fill(Theme.accent.opacity(0.18))
                    .blur(radius: 4)
                RookSilhouetteShape()
                    .fill(LinearGradient(
                        colors: [Theme.text, Theme.rookSilverMid, Theme.secondaryText],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(9)
                RookSpecularLine()
                    .stroke(Theme.primaryWhite.opacity(0.45), lineWidth: 1.2)
                    .padding(9)
            }
            .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
            .liquidGlassCircle(tint: Theme.accent)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(minWidth: Theme.minimumTapTarget, minHeight: Theme.minimumTapTarget)
        .accessibilityLabel("Kit Settings")
        .accessibilityAddTraits(.isButton)
    }
}
