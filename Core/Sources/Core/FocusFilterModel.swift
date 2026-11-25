import Foundation
import Observation

/// Visual styling tokens for an AI Focus filter ring.
public struct FocusStyle: Codable, Equatable, Sendable {
    public var iconName: String
    public var hexAccent: String

    public init(iconName: String = "scope", hexAccent: String = DesignTokens.accent.dark) {
        self.iconName = iconName
        self.hexAccent = hexAccent
    }
}

/// One locally persisted AI Focus lens that filters Home, Inbox, and Tasks.
public struct FocusFilter: Codable, Equatable, Identifiable, Sendable {
    public static let factoryID = "factory"
    public static let personalID = "personal"

    public var id: String
    public var label: String
    public var purpose: String
    public var iconName: String
    public var hexAccent: String

    public init(id: String, label: String, purpose: String, style: FocusStyle = FocusStyle()) {
        self.id = id
        self.label = label
        self.purpose = purpose
        self.iconName = style.iconName
        self.hexAccent = style.hexAccent
    }

    public var tokenColor: TokenColor {
        TokenColor(light: hexAccent, dark: hexAccent)
    }

    public var isBuiltIn: Bool {
        id == Self.factoryID || id == Self.personalID
    }

    public static let defaults: [FocusFilter] = [
        FocusFilter(
            id: factoryID,
            label: "Factory",
            purpose: "Software factory, engineering, code, builds, Swift, agents, and automation",
            style: FocusStyle(iconName: "sparkles", hexAccent: DesignTokens.indigoAccent.dark)
        ),
        FocusFilter(
            id: personalID,
            label: "Personal",
            purpose: "Home, family, health, errands, travel, and personal life",
            style: FocusStyle(iconName: "heart", hexAccent: "#E879F9")
        ),
    ]

    /// Deterministic keyword/phrase screening from label and purpose.
    public func matches(text: String, tags: [String] = []) -> Bool {
        let keywords = screeningKeywords
        guard !keywords.isEmpty else { return true }
        let haystack = (text + " " + tags.joined(separator: " ")).lowercased()
        let labelLower = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !labelLower.isEmpty, haystack.contains(labelLower) { return true }
        let words = Set(Self.tokenize(haystack))
        return keywords.contains { token in
            words.contains { word in
                word == token
                    || (token.count >= 5 && word.hasPrefix(token))
                    || (word.count >= 5 && token.hasPrefix(word))
            }
        }
    }

    private var screeningKeywords: [String] {
        let labelTokens = Self.tokenize(label.lowercased()).filter { $0.count >= 2 }
        let purposeTokens = Self.tokenize(purpose.lowercased())
            .filter { $0.count >= 3 && !Self.stopWords.contains($0) }
        return Array(Set(labelTokens + purposeTokens))
    }

    private static func tokenize(_ text: String) -> [String] {
        text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static let stopWords: Set<String> = [
        "and", "the", "for", "with", "this", "that", "against", "from", "into",
        "all", "future", "ideas", "screens", "screen", "are", "was", "were",
        "our", "your", "about", "using", "only", "life"
    ]
}

private struct FocusStoreEnvelope: Codable {
    var version: Int
    var filters: [FocusFilter]
}

/// Atomic JSON store for custom and default AI Focus entries in Application Support.
public final class FocusFilterStore: @unchecked Sendable {
    public static let currentVersion = 1
    public static let fileName = "focus-filters.json"

    private let files: any FileStore

    public init(files: any FileStore) {
        self.files = files
    }

    public func load() -> [FocusFilter] {
        guard let data = try? files.read(Self.fileName),
              let envelope = try? JSONDecoder().decode(FocusStoreEnvelope.self, from: data),
              envelope.version <= Self.currentVersion,
              !envelope.filters.isEmpty
        else {
            return FocusFilter.defaults
        }
        return envelope.filters
    }

    public func save(_ filters: [FocusFilter]) {
        let envelope = FocusStoreEnvelope(version: Self.currentVersion, filters: filters)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        try? files.write(data, name: Self.fileName)
    }
}

/// Observable Focus state powering Home Focus rings, Bento filtering, and Brief screening signals.
@MainActor @Observable
public final class FocusFilterModel {
    public private(set) var filters: [FocusFilter]
    public private(set) var activeFilterID: String?

    @ObservationIgnored private let store: FocusFilterStore?

    private static let palette: [(icon: String, hex: String)] = [
        ("scope", DesignTokens.glowTeal.dark),
        ("bolt", DesignTokens.accent.dark),
        ("leaf", DesignTokens.emeraldApprove.dark),
        ("sun.max", DesignTokens.glowAmber.dark),
        ("star", DesignTokens.glowPurple.dark),
    ]

    public init(store: FocusFilterStore? = nil) {
        self.store = store
        self.filters = store?.load() ?? FocusFilter.defaults
    }

    public convenience init(files: any FileStore) {
        self.init(store: FocusFilterStore(files: files))
    }

    public var activeFilter: FocusFilter? {
        guard let activeFilterID else { return nil }
        return filters.first { $0.id == activeFilterID }
    }

    public func toggleActive(id: String) {
        if activeFilterID == id {
            activeFilterID = nil
        } else if filters.contains(where: { $0.id == id }) {
            activeFilterID = id
        }
    }

    public func clearFilter() {
        activeFilterID = nil
    }

    @discardableResult
    public func addCustomFocus(label: String, purpose: String) -> FocusFilter? {
        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanLabel.isEmpty else { return nil }
        let cleanPurpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        let customCount = filters.filter { !$0.isBuiltIn }.count
        let chosen = Self.palette[customCount % Self.palette.count]
        let filter = FocusFilter(
            id: uniqueID(for: cleanLabel),
            label: cleanLabel,
            purpose: cleanPurpose.isEmpty ? cleanLabel : cleanPurpose,
            style: FocusStyle(iconName: chosen.icon, hexAccent: chosen.hex)
        )
        filters.append(filter)
        store?.save(filters)
        return filter
    }

    public func removeCustomFocus(id: String) {
        guard let index = filters.firstIndex(where: { $0.id == id && !$0.isBuiltIn }) else { return }
        if activeFilterID == id { activeFilterID = nil }
        filters.remove(at: index)
        store?.save(filters)
    }

    public func matches(text: String, tags: [String] = []) -> Bool {
        activeFilter?.matches(text: text, tags: tags) ?? true
    }

    private func uniqueID(for label: String) -> String {
        let slug = label.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: "-")
        let base = slug.isEmpty ? "focus" : slug
        if !filters.contains(where: { $0.id == base }) { return base }
        var suffix = 2
        while filters.contains(where: { $0.id == "\(base)-\(suffix)" }) { suffix += 1 }
        return "\(base)-\(suffix)"
    }
}
