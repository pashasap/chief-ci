import Foundation

/// The kinds of metadata code a task note may carry, in the order the code sheet lists them.
public enum TaskCodeKind: Int, CaseIterable, Sendable {
    case proposal, capture, action, feedback, question, result, other
}

/// One metadata code found in a note, with the kind that decides where it is listed.
public struct TaskCode: Equatable, Sendable {
    public var code: String
    public var kind: TaskCodeKind
}

/// What a task tile may show: its text without codes, and at most one proposed-or-taken-action line.
/// Codes themselves stay in the More sheet, described by `TaskMetadataScreen`.
public enum TaskTileText {
    /// A tile never shows more than one summary line.
    public static let summaryLineLimit = 1

    private static let takenLabel = "taken action"
    private static let proposedLabel = "proposed action"
    private static let separator: Character = "|"

    /// The task text with every metadata code removed, whitespace collapsed.
    public static func text(_ raw: String) -> String {
        clean(replacingCodes(in: raw))
    }

    /// The action prose of `note`: a taken action wins over a proposed one. Nil when neither has prose.
    public static func actionSummary(_ note: String?) -> String? {
        guard let note else { return nil }
        var proposed: String?
        for line in note.split(whereSeparator: \.isNewline) {
            let (label, rest) = labelAndRest(String(line))
            guard let prose = prose(of: rest) else { continue }
            if label == takenLabel { return prose }
            if label == proposedLabel, proposed == nil { proposed = prose }
        }
        return proposed
    }

    /// Every code in `note`, without duplicates, grouped by kind and in first-appearance order inside a kind.
    public static func codes(_ note: String?) -> [String] {
        guard let note else { return [] }
        var found: [TaskCode] = []
        var seen: Set<String> = []
        for code in matches(in: note) where !seen.contains(code) {
            seen.insert(code)
            found.append(TaskCode(code: code, kind: kind(of: code)))
        }
        return found.enumerated()
            .sorted { ($0.element.kind.rawValue, $0.offset) < ($1.element.kind.rawValue, $1.offset) }
            .map { $0.element.code }
    }

    // MARK: Parsing

    private static func labelAndRest(_ line: String) -> (label: String?, rest: String) {
        guard let colon = line.firstIndex(of: ":") else { return (nil, line) }
        let label = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        return (label, String(line[line.index(after: colon)...]))
    }

    /// The prose after the action's code separator; nil when the line carries no prose.
    static func prose(of rest: String) -> String? {
        guard let separatorIndex = rest.firstIndex(of: separator) else { return nil }
        let prose = clean(replacingCodes(in: String(rest[rest.index(after: separatorIndex)...])))
        return prose.isEmpty ? nil : prose
    }

    static func replacingCodes(in text: String) -> String {
        var result = text
        for code in matches(in: text) {
            result = result.replacingOccurrences(of: code, with: " ")
        }
        return result
    }

    static func clean(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
            .joined(separator: " ")
    }

    static func matches(in text: String) -> [String] {
        guard let pattern = codePattern else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return pattern.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    // Exactly the server handle formats: prefix P, A, Q, R, FB or c, then digits, then one or more
    // hyphen-digit groups. Examples: P-1116-3, c1115-04-1, A-1116-1, Q-1113-1, FB-123.
    // A bare date such as 2026-11-17 and look-alikes such as TK-1984, ABC-12 or X-77-2 never match.
    private static let codePattern = try? NSRegularExpression(
        pattern: "(?<![A-Za-z0-9])(?:FB|[PAQRc])\\d*(?:-\\d+)+(?![A-Za-z0-9])")

    static func kind(of code: String) -> TaskCodeKind {
        let upper = code.uppercased()
        if upper.hasPrefix("FB-") { return .feedback }
        if upper.hasPrefix("P-") { return .proposal }
        if upper.hasPrefix("Q-") { return .question }
        if upper.hasPrefix("R-") { return .result }
        if upper.hasPrefix("A-") { return .action }
        if code.first == "c" { return .capture }
        return .other
    }
}
