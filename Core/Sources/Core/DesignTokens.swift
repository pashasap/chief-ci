import Foundation

/// A colour with a light and a dark value, as "#RRGGBB" hex strings.
public struct TokenColor: Equatable, Sendable {
    public var light: String
    public var dark: String

    public init(light: String, dark: String) {
        self.light = light
        self.dark = dark
    }
}

/// The single source of colour and shape for every screen.
public enum DesignTokens {
    public static let accent = TokenColor(light: "#0A6B58", dark: "#4FC3A8")
    public static let background = TokenColor(light: "#F2F2F7", dark: "#000000")
    public static let card = TokenColor(light: "#FFFFFF", dark: "#1C1C1E")
    public static let destructive = TokenColor(light: "#D93025", dark: "#FF6B60")
    public static let recordRed = TokenColor(light: "#D93025", dark: "#D93025")
    public static let amber = TokenColor(light: "#9A6200", dark: "#FFB340")
    public static let text = TokenColor(light: "#1C1C1E", dark: "#F2F2F7")
    public static let secondaryText = TokenColor(light: "#6C6C70", dark: "#AEAEB2")
    /// The recording view is dark in both schemes.
    public static let recordBackground = TokenColor(light: "#121419", dark: "#121419")
    public static let recordText = TokenColor(light: "#F2F2F0", dark: "#F2F2F0")
    public static let cornerRadius: Double = 14
}
