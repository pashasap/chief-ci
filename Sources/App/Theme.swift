import SwiftUI
import UIKit
import Core

/// SwiftUI colours built from the Core design tokens. No colour value lives here.
enum Theme {
    static let background = color(DesignTokens.background)
    static let card = color(DesignTokens.card)
    static let text = color(DesignTokens.text)
    static let secondaryText = color(DesignTokens.secondaryText)
    static let accent = color(DesignTokens.accent)
    static let destructive = color(DesignTokens.destructive)
    static let amber = color(DesignTokens.amber)
    static let recordBackground = color(DesignTokens.recordBackground)
    static let recordText = color(DesignTokens.recordText)
    static let recordButton = color(DesignTokens.recordRed)
    static let cornerRadius = CGFloat(DesignTokens.cornerRadius)

    private static func color(_ token: TokenColor) -> Color {
        Color(UIColor { traits in uiColor(traits.userInterfaceStyle == .dark ? token.dark : token.light) })
    }

    private static func uiColor(_ hex: String) -> UIColor {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
