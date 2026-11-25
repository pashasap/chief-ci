import SwiftUI
import UIKit
import Core

/// SwiftUI colours and metrics built from the Core design tokens. No hex literal lives here.
enum Theme {
    static let canvas = color(DesignTokens.canvas)
    static let ambientSecondary = color(DesignTokens.ambientSecondary)
    static let surfaceDeep = color(DesignTokens.surfaceDeep)
    static let glassBaseTop = color(DesignTokens.glassBaseTop)
    static let glassBaseMid = color(DesignTokens.glassBaseMid)
    static let glassBaseBottom = color(DesignTokens.glassBaseBottom)
    static let primaryWhite = color(DesignTokens.primaryWhite)

    static let background = color(DesignTokens.background)
    static let card = color(DesignTokens.card)
    static let text = color(DesignTokens.text)
    static let secondaryText = color(DesignTokens.secondaryText)
    static let accent = color(DesignTokens.accent)
    static let heroStart = color(DesignTokens.heroStart)
    static let heroMid = color(DesignTokens.heroMid)
    static let heroEnd = color(DesignTokens.heroEnd)
    static let indigoAccent = color(DesignTokens.indigoAccent)
    static let emeraldApprove = color(DesignTokens.emeraldApprove)
    static let roseReject = color(DesignTokens.roseReject)
    static let warning = color(DesignTokens.warning)
    static let destructive = color(DesignTokens.destructive)
    static let amber = color(DesignTokens.amber)

    static let glowBlue = color(DesignTokens.glowBlue)
    static let glowTeal = color(DesignTokens.glowTeal)
    static let glowPurple = color(DesignTokens.glowPurple)
    static let glowAmber = color(DesignTokens.glowAmber)
    static let glowCyan = color(DesignTokens.glowCyan)

    static let rookBackdropTop = color(DesignTokens.rookBackdropTop)
    static let rookBackdropBottom = color(DesignTokens.rookBackdropBottom)
    static let rookSilverMid = color(DesignTokens.rookSilverMid)

    static let selectedTabFill = color(DesignTokens.selectedTabFill)
    static let selectedTabLabel = color(DesignTokens.selectedTabLabel)
    static let recordBackground = color(DesignTokens.recordBackground)
    static let recordText = color(DesignTokens.recordText)
    static let recordButton = color(DesignTokens.recordRed)

    static let cornerRadius = CGFloat(DesignTokens.cornerRadius)
    static let glassTileCornerRadius = CGFloat(DesignTokens.glassTileCornerRadius)
    static let pillCornerRadius = CGFloat(DesignTokens.pillCornerRadius)
    static let orbDiameter = CGFloat(DesignTokens.orbDiameter)
    static let radialCircleDiameter = CGFloat(DesignTokens.radialCircleDiameter)
    static let minimumTapTarget = CGFloat(DesignTokens.minimumTapTarget)
    static let compactTabHeight = CGFloat(DesignTokens.compactTabHeight)

    static func color(_ token: TokenColor) -> Color {
        Color(UIColor { traits in uiColor(traits.userInterfaceStyle == .dark ? token.dark : token.light) })
    }

    private static func uiColor(_ hex: String) -> UIColor {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
