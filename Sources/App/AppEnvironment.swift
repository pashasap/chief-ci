import Foundation
import Core

/// Wires the Core models to the real adapters. No logic lives here.
@MainActor
final class AppEnvironment {
    let coordinator = AppCoordinator()
    let inbox: InboxModel
    let decisions: DecisionModel
    let corrections: CorrectionModel
    let today: TodayModel
    let recording: RecordingModel
    let typed: TypedCaptureModel
    let settings: SettingsModel
    let notifications: SystemNotifications
    let reminders: ReminderModel
    let loop: AppLoop
    let uploader: UploadEngine
    private let outbox: OutboxStore
    private let transport: URLSessionTransport
    private let pairing: Pairing

    init() {
        let transport = URLSessionTransport()
        let tokens = KeychainTokenStore()
        let file = UserDefaultsSettings()
        let files = DirectoryFileStore(folderName: "chief")
        let clock = SystemClock()
        let pairing = Pairing(tokenStore: tokens, settings: file)
        let store = OutboxStore(files: files)
        let repository = SnapshotRepository(
            transport: transport, pairing: pairing, cache: SnapshotCache(files: files), clock: clock)
        repository.diagnostics = DiagnosticsStore(files: files, clock: clock)
        inbox = InboxModel(repository: repository, store: store, clock: clock)
        decisions = DecisionModel(inbox: inbox, transport: transport, pairing: pairing, clock: clock)
        corrections = CorrectionModel(decisions: decisions, inbox: inbox, transport: transport, pairing: pairing)
        today = TodayModel(inbox: inbox, decisions: decisions)
        uploader = UploadEngine(store: store, transport: transport, pairing: pairing, clock: clock)
        typed = TypedCaptureModel(store: store, clock: clock, ids: RandomIDs())
        recording = Self.makeRecording(store: store, uploader: uploader, clock: clock)
        let services = SettingsServices(
            files: files, clock: clock, timeZone: .current, transcribers: SystemTranscriber.availability)
        let settingsModel = SettingsModel(
            transport: transport, tokenStore: tokens, settings: file, services: services)
        settingsModel.appVersion =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        settings = settingsModel
        outbox = store
        self.transport = transport
        self.pairing = pairing
        inbox.coordinator = coordinator
        let coordinator = self.coordinator
        let notifications = SystemNotifications { identifier in coordinator.open(notificationIdentifier: identifier) }
        self.notifications = notifications
        let provision = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision").flatMap { try? Data(contentsOf: $0) }
        let reminders = ReminderModel(center: notifications, provision: provision, preferences: UserDefaultsReminderPreference())
        self.reminders = reminders
        settings.reminders = reminders
        loop = AppLoop(inbox: inbox, uploader: uploader, clock: clock,
            dependencies: AppLoopDependencies(recording: recording, reminders: reminders, settings: settings, typed: typed))
    }

    /// Sends what waits in the outbox, then refetches: on coming to the foreground and after a capture is saved.
    func sync() async {
        await loop.captureClosed()
    }

    /// The sheet model for a tapped result in the Brief tab.
    func resultSheet(handle: String) -> ResultSheetModel {
        ResultSheetModel(handle: handle, inbox: inbox, transport: transport, pairing: pairing)
    }

    private static func makeRecording(store: OutboxStore, uploader: UploadEngine, clock: SystemClock) -> RecordingModel {
        let environment = RecordingEnvironment(
            clock: clock, ids: RandomIDs(), haptics: SystemHaptics(), lease: SystemLease())
        let pipeline = RecordingPipeline(
            recorder: AudioRecorderAdapter(), speech: SystemTranscriber(kind: .speech),
            dictation: SystemTranscriber(kind: .dictation), uploader: uploader)
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        return RecordingModel(store: store, environment: environment, pipeline: pipeline, osMajor: major)
    }

    func capture(id: String) -> CaptureDetailModel? {
        guard let snapshot = inbox.snapshot, let capture = snapshot.captures.first(where: { $0.id == id }) else { return nil }
        return CaptureDetailModel(capture: capture, snapshot: snapshot, decisions: decisions)
    }

    /// The sheet content for a tapped inbox row.
    func detail(for row: RecentRow) -> CaptureDetailModel {
        if let snapshot = inbox.snapshot, let capture = snapshot.captures.first(where: { $0.id == row.captureId }) {
            return CaptureDetailModel(capture: capture, snapshot: snapshot, decisions: decisions)
        }
        let waiting = row.record
        let record = waiting ?? .typed(clientId: "none", recordedAt: Date(), text: row.text)
        return CaptureDetailModel(record: record)
    }
}
