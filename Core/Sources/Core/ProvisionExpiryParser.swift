import Foundation

/// Reads the expiry date out of the bytes of embedded.mobileprovision (a signed blob that embeds a plist).
public enum ProvisionExpiryParser {
    private static let key = "<key>ExpirationDate</key>"
    private static let open = "<date>"
    private static let close = "</date>"

    public static func expiry(from data: Data) -> Date? {
        let text = String(decoding: data, as: UTF8.self)
        guard let keyRange = text.range(of: key) else { return nil }
        let rest = text[keyRange.upperBound...].drop { $0.isWhitespace }
        guard rest.hasPrefix(open) else { return nil }
        let afterOpen = rest.dropFirst(open.count)
        guard let end = afterOpen.range(of: close) else { return nil }
        let value = afterOpen[..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return ISO8601DateFormatter().date(from: value)
    }
}
