import Foundation

public struct NeedsYouRow: Equatable, Sendable {
    public var label: String
    public var text: String
    public var lineLimit: Int = 3
}

public struct RecentRow: Equatable, Sendable {
    public var text: String
    public var status: String
    public var lineLimit: Int = 3
    /// The server's message of a capture in "Needs attention".
    public var detail: String?
    /// The server's capture id, for a capture in the snapshot.
    public var captureId: String?
    /// The outbox record, for a capture still on this iPhone.
    public var record: OutboxRecord?
}

public enum InboxRows {
    static func needsYou(_ snapshot: Snapshot) -> [NeedsYouRow] {
        var rows: [NeedsYouRow] = []
        for proposal in snapshot.proposals where proposal.state == "open" {
            rows.append(NeedsYouRow(label: "Kit suggests", text: proposal.would))
        }
        for question in snapshot.questions where question.state == "open" {
            rows.append(NeedsYouRow(label: "Kit asks", text: question.question))
        }
        for row in snapshot.unreadable {
            rows.append(NeedsYouRow(label: "Unreadable", text: "\(row.file): \(row.text ?? "")"))
        }
        return rows
    }

    /// The one row that reports undecodable snapshot elements, or nil when none were skipped.
    static func skipText(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        let items = count == 1 ? "1 item could not be shown." : "\(count) items could not be shown."
        return items + " See Settings, Diagnostics."
    }

    static func statusLabel(_ status: String) -> String {
        switch status {
        case "on_server": return "With Kit"
        case "filing": return "Kit is filing it"
        case "filed": return "Filed"
        case "needs_attention": return "Needs attention"
        default: return status
        }
    }

    static func recent(snapshot: Snapshot?, outbox: [OutboxRecord]) -> [RecentRow] {
        var entries: [(Date, RecentRow)] = []
        let zone = timeZone(snapshot?.timezone)
        let known = Set(snapshot?.captures.compactMap(\.clientId) ?? [])
        for capture in snapshot?.captures ?? [] {
            var row = RecentRow(text: capture.text, status: statusLabel(capture.status))
            row.captureId = capture.id
            entries.append((date(of: capture, in: zone), row))
        }
        for record in outbox where !known.contains(record.clientId) {
            var row = RecentRow(text: waitingText(record), status: "On this iPhone")
            row.record = record
            if let refusal = record.refusal {
                row.status = "Needs attention"
                row.detail = refusal
            }
            entries.append((record.recordedAt, row))
        }
        let indexed = entries.enumerated().sorted {
            ($0.element.0, $1.offset) > ($1.element.0, $0.offset)
        }
        return indexed.map { $0.element.1 }
    }

    /// The row text of a capture that is still on this iPhone.
    static func waitingText(_ record: OutboxRecord) -> String {
        record.text.isEmpty ? noTranscriptText : record.text
    }

    public static let noTranscriptText = "No transcript on this iPhone"

    static func timeZone(_ identifier: String?) -> TimeZone {
        identifier.flatMap { TimeZone(identifier: $0) } ?? TimeZone(identifier: "UTC") ?? .current
    }

    static func clockText(_ date: Date, in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func date(of capture: Capture, in zone: TimeZone) -> Date {
        guard let day = capture.date, let time = capture.time else { return .distantPast }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: day + " " + time) ?? .distantPast
    }
}
