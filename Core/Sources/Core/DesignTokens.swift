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

/// The single source of Obsidian Liquid Glass colour and shape for every screen.
public enum DesignTokens {
    public static let canvas = TokenColor(light: "#020307", dark: "#020307")
    public static let ambientSecondary = TokenColor(light: "#05070E", dark: "#05070E")
    public static let surfaceDeep = TokenColor(light: "#0F172A", dark: "#0F172A")
    public static let glassBaseTop = TokenColor(light: "#FFFFFF", dark: "#FFFFFF")
    public static let glassBaseMid = TokenColor(light: "#121726", dark: "#121726")
    public static let glassBaseBottom = TokenColor(light: "#090C16", dark: "#090C16")
    public static let primaryWhite = TokenColor(light: "#FFFFFF", dark: "#FFFFFF")

    public static let accent = TokenColor(light: "#38BDF8", dark: "#38BDF8")
    public static let heroStart = TokenColor(light: "#7DD3FC", dark: "#7DD3FC")
    public static let heroMid = TokenColor(light: "#99F6E4", dark: "#99F6E4")
    public static let heroEnd = TokenColor(light: "#E0F2FE", dark: "#E0F2FE")
    public static let indigoAccent = TokenColor(light: "#6366F1", dark: "#6366F1")
    public static let emeraldApprove = TokenColor(light: "#34D399", dark: "#34D399")
    public static let roseReject = TokenColor(light: "#FB7185", dark: "#FB7185")

    public static let glowBlue = TokenColor(light: "#3B82F6", dark: "#3B82F6")
    public static let glowTeal = TokenColor(light: "#2DD4BF", dark: "#2DD4BF")
    public static let glowPurple = TokenColor(light: "#8B5CF6", dark: "#8B5CF6")
    public static let glowAmber = TokenColor(light: "#F59E0B", dark: "#F59E0B")
    public static let glowCyan = TokenColor(light: "#22D3EE", dark: "#22D3EE")

    public static let rookBackdropTop = TokenColor(light: "#1E293B", dark: "#1E293B")
    public static let rookBackdropBottom = TokenColor(light: "#030712", dark: "#030712")
    public static let rookSilverMid = TokenColor(light: "#BAE6FD", dark: "#BAE6FD")

    public static let background = TokenColor(light: "#020307", dark: "#020307")
    public static let card = TokenColor(light: "#0B101E", dark: "#0B101E")
    public static let selectedTabFill = TokenColor(light: "#172542", dark: "#172542")
    public static let selectedTabLabel = TokenColor(light: "#E0F2FE", dark: "#E0F2FE")
    public static let warning = TokenColor(light: "#F59E0B", dark: "#F59E0B")
    public static let destructive = TokenColor(light: "#FB7185", dark: "#FB7185")
    public static let recordRed = TokenColor(light: "#FB7185", dark: "#FB7185")
    public static let amber = TokenColor(light: "#F59E0B", dark: "#F59E0B")
    public static let text = TokenColor(light: "#F8FAFC", dark: "#F8FAFC")
    public static let secondaryText = TokenColor(light: "#94A3B8", dark: "#94A3B8")
    /// The recording view is dark in both schemes.
    public static let recordBackground = TokenColor(light: "#020307", dark: "#020307")
    public static let recordText = TokenColor(light: "#F8FAFC", dark: "#F8FAFC")

    public static let cornerRadius: Double = 14
    public static let glassTileCornerRadius: Double = 22
    public static let pillCornerRadius: Double = 999
    public static let orbDiameter: Double = 62
    public static let radialCircleDiameter: Double = 58
    public static let minimumTapTarget: Double = 44
    public static let compactTabHeight: Double = 56
    public static let switchTrackWidth: Double = 51
    public static let switchTrackHeight: Double = 31
    public static let switchKnobInset: Double = 2
}
