import Foundation

/// The name shown in the Home greeting, as entered in Settings.
///
/// The name is trimmed, and capped so a long paste cannot break the hero layout.
/// An empty or whitespace-only input carries no name at all.
public enum GreetingName {
    public static let maxLength = 40

    public static func sanitize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(maxLength))
    }
}
