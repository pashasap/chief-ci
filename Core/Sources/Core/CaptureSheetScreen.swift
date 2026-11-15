import Foundation

public struct CaptureSheetRow: Equatable, Sendable {
    public var handle: String
    public var text: String
    public var label: String?
    public var queuedLine: String?
}

public struct CaptureSheetSection: Equatable, Sendable {
    public var title: String
    /// The said text, for "You said".
    public var text: String?
    /// Nil: not clamped.
    public var lineLimit: Int?
    public var rows: [CaptureSheetRow] = []
    /// Set when "Filed from this" has no rows.
    public var emptyText: String?
}

/// Everything the capture sheet shows, as plain values. The view renders this and nothing else.
@MainActor
public struct CaptureSheetScreen {
    public let title = "Capture"
    public let doneLabel = "Done"
    public let closeLabel = "Close capture"
    public let captureId: String
    public let sections: [CaptureSheetSection]
    public let status: String

    public init(detail: CaptureDetailModel) {
        captureId = detail.captureId
        status = detail.status
        let said = detail.youSaidText.isEmpty ? "Voice note" : detail.youSaidText
        var result = [CaptureSheetSection(title: detail.youSaidHeading, text: said, lineLimit: nil)]
        if !detail.isOnThisPhone {
            let rows = detail.items.map {
                CaptureSheetRow(handle: $0.handle, text: $0.text, label: $0.label, queuedLine: $0.queuedLine)
            }
            result.append(
                CaptureSheetSection(
                    title: detail.filedHeading, lineLimit: nil, rows: rows,
                    emptyText: rows.isEmpty ? "Nothing was filed from this." : nil))
        }
        sections = result
    }
}
