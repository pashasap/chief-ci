import Foundation

public enum MarkdownBlock: Equatable, Sendable {
    case heading(String)
    case listItem(String)
    case paragraph(String)
}

/// Turns Markdown into plain-text blocks: headings, list items and paragraphs.
public enum MarkdownBlocks {
    public static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }
        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
            } else if let text = heading(line) {
                flush()
                blocks.append(.heading(text))
            } else if let text = listItem(line) {
                flush()
                blocks.append(.listItem(text))
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }

    private static func heading(_ line: String) -> String? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else { return nil }
        let rest = line.dropFirst(hashes.count)
        guard rest.first == " " else { return nil }
        return rest.trimmingCharacters(in: .whitespaces)
    }

    private static func listItem(_ line: String) -> String? {
        guard let first = line.first, "-*+•".contains(first) else { return nil }
        let rest = line.dropFirst()
        guard rest.first == " " else { return nil }
        return rest.trimmingCharacters(in: .whitespaces)
    }
}
