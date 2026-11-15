import Foundation
import Observation

@MainActor
@Observable
public final class ReminderModel {
    public private(set) var isBriefReminderOn = false
    public private(set) var statusText: String?

    @ObservationIgnored private let center: any NotificationCenterPort
    @ObservationIgnored private let expiry: Date?
    @ObservationIgnored private let preferences: (any ReminderPreferenceStore)?
    @ObservationIgnored private var didRestore = false
    @ObservationIgnored private var briefTime: String?
    @ObservationIgnored private var timeZone = TimeZone.current

    /// `provision` is the bytes of embedded.mobileprovision, when the file exists.
    public init(center: any NotificationCenterPort, provision: Data?, preferences: (any ReminderPreferenceStore)? = nil) {
        self.center = center
        self.preferences = preferences
        self.expiry = provision.flatMap { ProvisionExpiryParser.expiry(from: $0) }
    }

    public func restore() async {
        guard !didRestore else { return }
        didRestore = true
        if preferences?.load() == true { await setBriefReminder(on: true) }
    }

    /// The text of the "This build stops opening on" row.
    public func expiryText(in zone: TimeZone) -> String {
        guard let expiry else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "d MMM yyyy, HH:mm"
        return formatter.string(from: expiry)
    }

    public func setBriefReminder(on: Bool) async {
        if on {
            guard !isBriefReminderOn else { return }
            guard await center.requestPermission() else {
                isBriefReminderOn = false
                preferences?.save(false)
                statusText = "Notifications are not allowed for Kit"
                return
            }
            statusText = nil
            isBriefReminderOn = true
            preferences?.save(true)
            await schedule()
        } else {
            isBriefReminderOn = false
            preferences?.save(false)
            statusText = nil
            await center.remove(identifier: NotificationIdentifier.briefReminder)
            await center.remove(identifier: NotificationIdentifier.signingReminder)
        }
    }

    public func apply(snapshot: Snapshot) async {
        let time = snapshot.settings?.briefTime
        let zone = snapshot.timezone.flatMap { TimeZone(identifier: $0) } ?? timeZone
        let changed = time != briefTime || zone != timeZone
        briefTime = time
        timeZone = zone
        if changed && isBriefReminderOn { await schedule() }
    }

    private func schedule() async {
        defer { statusText = center.problem }
        if let time = briefTime, let when = Self.reminderTime(from: time) {
            await center.schedule(
                NotificationRequest(
                    identifier: NotificationIdentifier.briefReminder, title: "Morning brief",
                    body: "Your brief is ready.",
                    trigger: .daily(hour: when.hour, minute: when.minute, timeZone: timeZone)))
        } else {
            await center.remove(identifier: NotificationIdentifier.briefReminder)
        }
        guard let expiry else { return }
        await center.schedule(
            NotificationRequest(
                identifier: NotificationIdentifier.signingReminder, title: "Kit needs re-signing",
                body: "This build stops opening in two days.",
                trigger: .once(expiry.addingTimeInterval(-2 * 86_400))))
    }

    /// brief_time plus five minutes, wrapping past midnight.
    static func reminderTime(from text: String) -> (hour: Int, minute: Int)? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
            (0..<24).contains(hour), (0..<60).contains(minute)
        else { return nil }
        let total = (hour * 60 + minute + 5) % 1440
        return (total / 60, total % 60)
    }
}
