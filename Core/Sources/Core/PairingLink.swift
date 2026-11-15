import Foundation

public enum PairingLinkError: Error, Equatable, Sendable {
    case invalidLink
}

public struct PairingLink: Equatable, Sendable {
    public let baseURL: String
    public let token: String

    public static func parse(_ text: String) throws -> PairingLink {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: trimmed),
              parts.scheme?.lowercased() == "chief",
              let items = parts.queryItems,
              let base = items.first(where: { $0.name == "base" })?.value,
              let token = items.first(where: { $0.name == "token" })?.value,
              !token.isEmpty
        else { throw PairingLinkError.invalidLink }
        guard let cleanBase = normalize(base) else { throw PairingLinkError.invalidLink }
        return PairingLink(baseURL: cleanBase, token: token)
    }

    private static func normalize(_ base: String) -> String? {
        var text = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URLComponents(string: text),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return text
    }
}
