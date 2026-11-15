import Foundation

public struct SettingsEntry: Equatable, Sendable {
    public var label: String
    public var value: String
}

public enum SettingsAction: Equatable, Sendable { case pasteLink, checkServer, unpair, copyDiagnostics }

public struct SettingsControl: Equatable, Sendable {
    public var label: String
    public var action: SettingsAction
    public var role: ControlRole
    public var isEnabled: Bool
}

/// Everything the settings screen shows, as plain values. The view renders this and nothing else.
public struct SettingsScreen: Equatable, Sendable {
    public let title = "Settings"
    public let statusTitle = "Status"
    public let pairTitle = "Pair"
    public let pairingLinkLabel = "Pairing link"
    public let pairLinkHint = "Pair with this link"
    public let unpairTitle = "Unpair this iPhone?"
    public let unpairLabel = "Unpair"
    public let cancelLabel = "Cancel"
    public let unpairExplanation = "Captures waiting on this iPhone are kept."
    public let entries: [SettingsEntry]
    public let explanation: String?
    public let controls: [SettingsControl]
    public let reminders: RemindersSection
    public let checkResult: String?
    public let diagnostics: DiagnosticsSection

    @MainActor
    public init(model: SettingsModel) {
        let paired = model.isPaired
        checkResult = model.checkResult
        diagnostics = DiagnosticsSection(
            title: "Diagnostics", rows: model.diagnosticsRows,
            copyControl: SettingsControl(
                label: "Copy diagnostics", action: .copyDiagnostics, role: .normal, isEnabled: true))
        entries = model.entries
        reminders = RemindersSection(reminders: model.reminders, timeZone: model.timeZone)
        explanation = paired ? nil : "Captures are waiting on this iPhone until you pair"
        controls = [
            SettingsControl(label: "Paste link", action: .pasteLink, role: .normal, isEnabled: true),
            SettingsControl(label: "Check server", action: .checkServer, role: .normal, isEnabled: paired),
            SettingsControl(label: "Unpair", action: .unpair, role: .destructive, isEnabled: paired),
        ]
    }
}
