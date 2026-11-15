import Foundation

public protocol ReminderPreferenceStore: Sendable {
    func load() -> Bool
    func save(_ enabled: Bool)
}
