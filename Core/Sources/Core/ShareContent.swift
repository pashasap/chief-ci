import Foundation
import Observation

/// Turns a title into a safe file name: letters, digits, spaces, hyphens and dots, 80 characters at most.
public enum ShareFileName {
    public static let maxLength = 80
    static let fallback = "Kit share"

    public static func make(title: String, ext: String) -> String {
        let suffix = "." + ext
        let allowed = CharacterSet.letters.union(.decimalDigits).union(CharacterSet(charactersIn: " -."))
        let kept = String(String.UnicodeScalarView(title.unicodeScalars.filter { allowed.contains($0) }))
        var stem = kept.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        if stem.isEmpty { stem = fallback }
        stem = String(stem.prefix(max(1, maxLength - suffix.count)))
        stem = stem.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        if stem.isEmpty { stem = "x" }
        return stem + suffix
    }
}

/// The text and the file name that a share carries.
public struct ShareContent: Equatable, Sendable {
    public var text: String
    public var fileName: String

    public static func result(title: String, markdown: String) -> ShareContent {
        ShareContent(text: markdown, fileName: ShareFileName.make(title: title, ext: "md"))
    }

    public static func draft(title: String, markdown: String) -> ShareContent {
        ShareContent(text: markdown, fileName: ShareFileName.make(title: title, ext: "md"))
    }

    public static func brief(date: String, lines: [String]) -> ShareContent {
        ShareContent(
            text: lines.joined(separator: "\n"),
            fileName: ShareFileName.make(title: "Brief " + date, ext: "md"))
    }
}

public struct ShareControl: Equatable, Sendable {
    public var label: String
    public var text: String?
    public var isEnabled: Bool
    public var disabledReason: String?
}

/// Where temporary share files live; the app's share FileStore is rooted here.
public enum ShareFolder {
    public static var url: URL { FileManager.default.temporaryDirectory.appendingPathComponent("chief-share") }
}

/// The 'Share' and 'Share as file' controls for one piece of loaded content. Sends and tracks nothing.
@MainActor @Observable
public final class ShareControls {
    public let share: ShareControl
    public let shareAsFile: ShareControl
    public private(set) var fileURL: URL?

    private let content: ShareContent?
    private let files: any FileStore

    public init(content: ShareContent?, noContentReason: String, files: any FileStore) {
        self.content = content
        self.files = files
        share = Self.control("Share", content: content, reason: noContentReason)
        shareAsFile = Self.control("Share as file", content: content, reason: noContentReason)
    }

    private static func control(_ label: String, content: ShareContent?, reason: String) -> ShareControl {
        ShareControl(
            label: label, text: content?.text, isEnabled: content != nil,
            disabledReason: content == nil ? reason : nil)
    }

    /// Writes the text through the file store and exposes the URL; nil when there is no content.
    @discardableResult
    public func prepareFile() throws -> URL? {
        guard let content else { return nil }
        try files.write(Data(content.text.utf8), name: content.fileName)
        let url = ShareFolder.url.appendingPathComponent(content.fileName)
        fileURL = url
        return url
    }
}

extension ResultSheetModel {
    public func resultShare(files: any FileStore) -> ShareControls {
        let content = result.state == .loaded
            ? ShareContent.result(title: title, markdown: result.markdown) : nil
        return ShareControls(content: content, noContentReason: "The result is not loaded yet", files: files)
    }

    public func draftShare(files: any FileStore) -> ShareControls {
        let content = draft.state == .loaded
            ? ShareContent.draft(title: title, markdown: draft.markdown) : nil
        return ShareControls(content: content, noContentReason: "The draft is not loaded yet", files: files)
    }
}

extension BriefScreen {
    public func shareControls(files: any FileStore) -> ShareControls {
        var content: ShareContent?
        if let snapshot = inbox?.snapshot, let brief = snapshot.brief, brief.recorded {
            content = ShareContent.brief(date: snapshot.today ?? "", lines: brief.lines)
        }
        return ShareControls(content: content, noContentReason: "No brief was recorded today", files: files)
    }
}
