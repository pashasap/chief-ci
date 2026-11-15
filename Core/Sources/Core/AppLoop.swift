import Foundation
import Observation

/// What moves by itself: uploads, refreshes and polling. The app calls the event methods and runs
/// `nextDelay()` / `tick()` in one loop while it is in the foreground; Core decides what happens.
@MainActor
@Observable
public final class AppLoop {
    /// The loop never sleeps for less than this, whatever is due.
    public static let minimumDelay: TimeInterval = 1
    public private(set) var isForeground = false
    /// When the current polling stretch began; nil while nothing is pending.
    @ObservationIgnored private var pollStart: Date?

    @ObservationIgnored public let inbox: InboxModel
    @ObservationIgnored public let uploader: UploadEngine
    @ObservationIgnored private let clock: any Clock
    @ObservationIgnored private weak var recording: RecordingModel?
    @ObservationIgnored private var reminders: ReminderModel?

    public init(
        inbox: InboxModel, uploader: UploadEngine, clock: any Clock, recording: RecordingModel? = nil,
        reminders: ReminderModel? = nil, settings: SettingsModel? = nil, typed: TypedCaptureModel? = nil
    ) {
        self.inbox = inbox
        self.uploader = uploader
        self.clock = clock
        self.recording = recording
        self.reminders = reminders
        inbox.uploader = uploader
        inbox.loop = self
        uploader.afterRun = { [weak self] in
            guard let self else { return }
            self.inbox.showCached()
            await self.inbox.refresh()
        }
        settings?.afterUnpair = { [weak self] in self?.inbox.showCached() }
        settings?.afterPairing = { [weak self] in await self?.paired() }
        typed?.afterSave = { [weak self] in
            self?.inbox.coordinator?.selectedTab = .inbox
            self?.inbox.showCached()
            Task { await self?.captureClosed() }
        }
        inbox.afterRefresh = { [weak self] snapshot in await self?.handOver(snapshot) }
    }

    /// After each refresh: the names list goes to the recording model, the brief time to the reminders.
    private func handOver(_ snapshot: Snapshot) async {
        recording?.vocabulary = snapshot.settings?.vocabulary ?? []
        await reminders?.apply(snapshot: snapshot)
    }

    // MARK: Events

    /// The app opened: the cached screens first, then send and fetch.
    public func launch() async {
        inbox.showCached()
        await becameActive()
    }

    public func becameActive() async {
        isForeground = true
        inbox.showCached()
        if let snapshot = inbox.snapshot { await handOver(snapshot) }
        await reminders?.restore()
        await sync()
    }

    public func leftForeground() {
        isForeground = false
        pollStart = nil
    }

    /// Pairing succeeded.
    public func paired() async { await sync() }

    /// The record or typed screen closed: the new capture is listed at once, then sent.
    public func captureClosed() async {
        if recording?.savedMessage != nil { inbox.coordinator?.selectedTab = .inbox }
        inbox.showCached()
        await sync()
    }

    /// "Retry now" on a waiting capture.
    public func retryNow() async {
        await uploader.retryNow()
    }

    /// Sends what waits in the outbox, then refetches.
    public func sync() async {
        await uploader.run()
    }

    // MARK: The loop

    /// Changes whenever the wait before the next tick may have changed, so the app restarts its sleep.
    public var wakeKey: String {
        let retry = uploader.nextRetry.map { String($0.timeIntervalSince1970) } ?? "-"
        return "\(isForeground)|\(inbox.needsPolling)|\(retry)"
    }

    /// Seconds until the next tick, or nil when nothing is due: in the background, or nothing pending.
    public func nextDelay() -> TimeInterval? {
        guard isForeground else { return nil }
        let now = clock.now
        var delays: [TimeInterval] = []
        if inbox.needsPolling {
            let start = pollStart ?? now
            if pollStart == nil { pollStart = now }
            if let interval = PollingPolicy.interval(
                elapsedSinceStart: now.timeIntervalSince(start), needsPolling: true, inForeground: true)
            {
                delays.append(interval)
            }
        } else {
            pollStart = nil
        }
        if uploader.status != "Not paired", let retry = uploader.nextRetry { delays.append(retry.timeIntervalSince(now)) }
        // Never zero: a retry can be due while another pass is still on the network, and tick() then returns at once.
        return delays.min().map { max(Self.minimumDelay, $0) }
    }

    /// One step of the loop: send a capture whose retry time arrived, and poll while something is pending.
    public func tick() async {
        guard isForeground else { return }
        if let retry = uploader.nextRetry, retry <= clock.now {
            await sync()
            return
        }
        if inbox.needsPolling { await inbox.refresh() }
    }
}
