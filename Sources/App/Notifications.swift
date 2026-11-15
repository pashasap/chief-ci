import Foundation
import UserNotifications
import Core

struct UserDefaultsReminderPreference: ReminderPreferenceStore {
    private let key = "chief.reminders.enabled"
    func load() -> Bool { UserDefaults.standard.bool(forKey: key) }
    func save(_ enabled: Bool) { UserDefaults.standard.set(enabled, forKey: key) }
}

final class SystemNotifications: NSObject, NotificationCenterPort, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let center = UNUserNotificationCenter.current()
    private let onTap: @MainActor @Sendable (String) -> Void
    private let lock = NSLock()
    private var failure: String?

    init(onTap: @escaping @MainActor @Sendable (String) -> Void) {
        self.onTap = onTap
        super.init()
        center.delegate = self
    }

    var problem: String? {
        lock.lock()
        defer { lock.unlock() }
        return failure
    }

    private func setProblem(_ text: String?) {
        lock.lock()
        defer { lock.unlock() }
        failure = text
    }

    func requestPermission() async -> Bool {
        setProblem(nil)
        do { return try await center.requestAuthorization(options: [.alert, .sound]) }
        catch { return false }
    }

    func schedule(_ request: NotificationRequest) async {
        guard Self.allowed(request.identifier) else { return }
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        let trigger: UNCalendarNotificationTrigger
        switch request.trigger {
        case .daily(let hour, let minute, let zone):
            var parts = DateComponents()
            parts.calendar = Calendar(identifier: .gregorian)
            parts.timeZone = zone
            parts.hour = hour
            parts.minute = minute
            trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)
        case .once(let date):
            guard date > Date() else { await remove(identifier: request.identifier); return }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
            var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            parts.timeZone = calendar.timeZone
            trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        }
        do { try await center.add(UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger)) }
        catch { setProblem(NotificationCopy.scheduleFailed) }
    }

    func remove(identifier: String) async {
        guard Self.allowed(identifier) else { return }
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let identifier = response.notification.request.identifier
        guard Self.allowed(identifier) else { return }
        await onTap(identifier)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        Self.allowed(notification.request.identifier) ? [.banner, .sound] : []
    }

    private static func allowed(_ identifier: String) -> Bool {
        identifier == NotificationIdentifier.briefReminder || identifier == NotificationIdentifier.signingReminder
    }
}
