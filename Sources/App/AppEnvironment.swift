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
    let reminders: ReminderModel
    private let notifications: any NotificationCenterPort
    let audit: LayoutAuditFixture?
    let loop: AppLoop
    let clock: any Core.Clock
    let uploader: UploadEngine
    private let outbox: OutboxStore
    private let transport: any HTTPTransport
    private let pairing: Pairing

    init(audit: LayoutAuditFixture? = nil) {
        self.audit = audit
        let transport: any HTTPTransport = if let audit { audit } else { URLSessionTransport() }
        let tokens: any TokenStore = if let audit { audit } else { KeychainTokenStore() }
        let file: any SettingsFile = if let audit { audit } else { UserDefaultsSettings() }
        let files: any FileStore = if let audit { audit } else { DirectoryFileStore(folderName: "chief") }
        let clock: any Core.Clock = if let audit { audit } else { SystemClock() }
        let ids: any UUIDSource = if let audit { audit } else { RandomIDs() }
        self.clock = clock
        let pairing = Pairing(tokenStore: tokens, settings: file)
        let store = OutboxStore(files: files)
        let diagnostics = DiagnosticsStore(files: files, clock: clock)
        let repository = SnapshotRepository(
            transport: transport, pairing: pairing, cache: SnapshotCache(files: files), clock: clock)
        repository.diagnostics = diagnostics
        inbox = InboxModel(repository: repository, store: store, clock: clock)
        decisions = DecisionModel(inbox: inbox, transport: transport, pairing: pairing, clock: clock)
        corrections = CorrectionModel(decisions: decisions, inbox: inbox, transport: transport, pairing: pairing)
        today = TodayModel(inbox: inbox, decisions: decisions, ideas: IdeaModel(inbox: inbox, decisions: decisions))
        uploader = UploadEngine(store: store, transport: transport, pairing: pairing, clock: clock)
        typed = TypedCaptureModel(store: store, clock: clock, ids: ids)
        let recordingServices = RecordingEnvironment(clock: clock, ids: ids,
            haptics: audit.map { $0 as any Haptics } ?? SystemHaptics(),
            lease: audit.map { $0 as any BackgroundLease } ?? SystemLease())
        let recordingModel = Self.makeRecording(RecordingWiring(
            store: store, uploader: uploader, environment: recordingServices,
            audit: audit, diagnostics: diagnostics))
        recording = recordingModel
        let transcribers = audit == nil ? SystemTranscriber.availability
            : TranscriberAvailability(speech: true, dictation: true)
        let services = SettingsServices(
            files: files, clock: clock, timeZone: .current, transcribers: transcribers
        ).withBundleMetadata(BundlePackageMetadata())
        let settingsModel = SettingsModel(
            transport: transport, tokenStore: tokens, settings: file, services: services)
        settingsModel.appVersion =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        settingsModel.recorder = recordingModel
        settings = settingsModel
        outbox = store
        self.transport = transport
        self.pairing = pairing
        inbox.coordinator = coordinator
        notifications = Self.makeNotifications(audit: audit, coordinator: coordinator)
        reminders = Self.makeReminders(center: notifications, isAudit: audit != nil)
        settings.reminders = reminders
        loop = AppLoop(inbox: inbox, uploader: uploader, clock: clock,
            dependencies: AppLoopDependencies(recording: recording, reminders: reminders, settings: settings, typed: typed))
    }

    /// Sends what waits in the outbox, then refetches: on coming to the foreground and after a capture is saved.
    func sync() async {
        await loop.captureClosed()
    }

    func openWrite() async {
        await coordinator.openWrite(recording: recording, typed: typed)
    }

    /// The sheet model for a tapped result in the Brief tab.
    func resultSheet(handle: String) -> ResultSheetModel {
        ResultSheetModel(handle: handle, inbox: inbox, transport: transport, pairing: pairing)
    }

    private static func makeNotifications(audit: LayoutAuditFixture?, coordinator: AppCoordinator) -> any NotificationCenterPort {
        if let audit { return audit }
        return SystemNotifications { identifier in coordinator.open(notificationIdentifier: identifier) }
    }

    private static func makeReminders(center: any NotificationCenterPort, isAudit: Bool) -> ReminderModel {
        if isAudit { return ReminderModel(center: center, provision: nil) }
        let provision = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision").flatMap { try? Data(contentsOf: $0) }
        return ReminderModel(center: center, provision: provision, preferences: UserDefaultsReminderPreference())
    }

    /// Everything the recording model needs, so one value carries it instead of a long parameter list.
    private struct RecordingWiring {
        let store: OutboxStore
        let uploader: UploadEngine
        let environment: RecordingEnvironment
        let audit: LayoutAuditFixture?
        let diagnostics: DiagnosticsStore
    }

    private static func makeRecording(_ wiring: RecordingWiring) -> RecordingModel {
        let pipeline: RecordingPipeline
        if let audit = wiring.audit {
            pipeline = RecordingPipeline(
                recorder: audit, speech: audit, dictation: audit, uploader: wiring.uploader)
        } else {
            pipeline = RecordingPipeline(
                recorder: AudioRecorderAdapter(diagnostics: wiring.diagnostics),
                speech: SystemTranscriber(kind: .speech),
                dictation: SystemTranscriber(kind: .dictation), uploader: wiring.uploader)
        }
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        return RecordingModel(
            store: wiring.store, environment: wiring.environment, pipeline: pipeline, osMajor: major)
    }

    func prepareAudit() async {
        guard let audit else { return }
        coordinator.selectedTab = audit.tab
        today.selectedSegment = 0
        await inbox.refresh()
        await audit.prepareCapture(coordinator: coordinator, recording: recording, typed: typed)
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
