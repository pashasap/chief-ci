import Foundation

/// The "Reminders" section of Settings, as plain values.
public struct RemindersSection: Equatable, Sendable {
    public var title: String
    public var switchLabel: String
    public var isOn: Bool
    public var statusText: String?
    public var entries: [SettingsEntry]

    @MainActor
    init(reminders: ReminderModel?, timeZone: TimeZone) {
        title = "Reminders"
        switchLabel = "Morning brief reminder"
        isOn = reminders?.isBriefReminderOn ?? false
        statusText = reminders?.statusText
        entries = [
            SettingsEntry(
                label: "This build stops opening on",
                value: reminders?.expiryText(in: timeZone) ?? "Unknown")
        ]
    }
}
