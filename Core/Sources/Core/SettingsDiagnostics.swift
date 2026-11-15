import Foundation

/// The "Diagnostics" section of Settings: four rows and the copy control.
public struct DiagnosticsSection: Equatable, Sendable {
    public var title: String
    public var rows: [SettingsEntry]
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
            SettingsEntry(label: "Waiting to send", value: String(OutboxStore(files: services.files).records().count)),
        ]
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

    /// Copies plain text with the four rows, the app version and the snapshot api number. No token, no address.
    public func copyDiagnostics(to clipboard: any ClipboardAdapter) {
        let api = SnapshotCache(files: services.files).load().map { String($0.snapshot.api) } ?? "none"
        var lines = ["Kit diagnostics", "App version: " + appVersion, "Snapshot api: " + api]
        for row in diagnosticsRows { lines.append(row.label + ": " + row.value) }
        clipboard.copy(lines.joined(separator: "\n"))
    }
}
