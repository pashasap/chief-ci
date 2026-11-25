import Foundation

/// The "Diagnostics" section of Settings: the rows R-77 names, the health facts R-104 adds, and Copy.
public struct DiagnosticsSection: Equatable, Sendable {
    public var title: String
    /// The four rows R-77 names, in order.
    public var rows: [SettingsEntry]
    /// The facts R-104 adds: outbox read health, package build and revision, the recorder reason.
    public var health: [SettingsEntry]
    public var copyControl: SettingsControl
}

extension SettingsModel {
    static let shownSkipLines = 5

    var diagnosticsRows: [SettingsEntry] {
        let state = diagnostics.load()
        let answer = state.answerAt.map { clockText($0) + ", " + String(state.answerStatus ?? 0) }
        let problem = state.problemText.map { text in
            state.problemAt.map { text + " " + clockText($0) } ?? text
        }
        return [
            SettingsEntry(label: "Last answer", value: answer ?? "None yet"),
            SettingsEntry(label: "Last problem", value: problem ?? "None"),
            SettingsEntry(label: "Items not shown", value: skipLines()),
            SettingsEntry(label: "Waiting to send", value: String(outboxReadable().records.count)),
            SettingsEntry(label: "Outbox read", value: outboxHealth()),
            SettingsEntry(label: "Package build", value: BundleMetadataText.build(services.bundleMetadata)),
            SettingsEntry(label: "Package revision", value: BundleMetadataText.revision(services.bundleMetadata)),
            SettingsEntry(label: "Record unavailable", value: recordUnavailable()),
        ]
    }

    /// The readable records, and the store notices of the same read, kept together on purpose.
    private func outboxReadable() -> (records: [OutboxRecord], notices: [String]) {
        let store = OutboxStore(files: services.files)
        let records = store.records()
        return (records, store.notices)
    }

    /// Redacted read health: never a bare count, and explicit when nothing in the outbox could be read.
    private func outboxHealth() -> String {
        let read = outboxReadable()
        if let notice = read.notices.first {
            var value = "unreadable, " + String(read.records.count) + " record(s) readable"
            value += " (" + notice + ")"
            if read.notices.count > 1 { value += " and " + String(read.notices.count - 1) + " more" }
            return value
        }
        return "readable, " + String(read.records.count) + " record(s) readable"
    }

    /// The recorder's own reason, or the explicit "available" value when nothing holds it.
    private func recordUnavailable() -> String {
        guard let reason = recorder?.recordAvailability.reason else { return "Available" }
        return reason.text
    }

    /// One line per skipped element, at most five, then "and N more"; "None" when nothing was skipped.
    private func skipLines() -> String {
        let skipped = SnapshotCache(files: services.files).load()?.skipped ?? []
        if skipped.isEmpty { return "None" }
        var lines = skipped.prefix(Self.shownSkipLines).map { $0.listName + ": " + $0.reason }
        if skipped.count > Self.shownSkipLines {
            lines.append("and \(skipped.count - Self.shownSkipLines) more")
        }
        return lines.joined(separator: "\n")
    }

    /// R-77's four rows, in order.
    static let rowLabels = ["Last answer", "Last problem", "Items not shown", "Waiting to send"]

    /// The four rows R-77 names; the Diagnostics section keeps them exactly as they were.
    var legacyDiagnosticsRows: [SettingsEntry] {
        diagnosticsRows.filter { Self.rowLabels.contains($0.label) }
    }

    /// The facts R-104 adds, rendered under the four rows.
    var factDiagnosticsRows: [SettingsEntry] {
        diagnosticsRows.filter { !Self.rowLabels.contains($0.label) }
    }

    /// Copies plain text with the rows, the app version and the snapshot api number. No token, no address.
    public func copyDiagnostics(to clipboard: any ClipboardAdapter) {
        let api = SnapshotCache(files: services.files).load().map { String($0.snapshot.api) } ?? "none"
        var lines = ["Kit diagnostics", "App version: " + appVersion, "Snapshot api: " + api]
        for row in diagnosticsRows { lines.append(row.label + ": " + row.value) }
        clipboard.copy(lines.joined(separator: "\n"))
    }
}
