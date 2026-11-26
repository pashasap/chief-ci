import Foundation

/// Isolated ports for the layout audit launches; nothing is loaded from or written to the device.
public final class LayoutAuditFixture: FileStore, Clock, UUIDSource, TokenStore, SettingsFile, HTTPTransport,
    RecorderProtocol, TranscriberProtocol, Haptics, BackgroundLease, NotificationCenterPort, @unchecked Sendable {
    public let stop: AuditStop
    public let tab: AppTab
    public var showsRecording: Bool { stop.id == "xl-today-recording" || stop.id == "recording-meter" }
    public let now = Date(timeIntervalSince1970: 1_794_916_800)
    public var elapsed: TimeInterval { stop.id == "recording-meter" ? 65 : 17 }
    public var level: Double { lock.withLock { sampleLevel } }
    private var sampleLevel = 0.42

    private let lock = NSLock()
    private var serial: UInt64 = 0
    private var files: [String: Data] = [:]

    public init?(id: String) {
        guard let stop = AuditStops.all.first(where: { $0.id == id }) else { return nil }
        self.stop = stop
        switch id {
        case "xl-today-recording": tab = .today
        case "xl-bottom-bar": tab = .brief
        default: tab = .inbox
        }
    }

    @MainActor
    public func prepareCapture(coordinator: AppCoordinator, recording: RecordingModel, typed: TypedCaptureModel) async {
        switch stop.id {
        case "independent-write":
            typed.text = "Bring the sample checklist.\nPick up the demo kit."
            await coordinator.openWrite(recording: recording, typed: typed)
        case "permission-recovery":
            await recording.start()
        case "xl-today-recording", "recording-meter":
            await recording.start()
            await seedMeter(recording)
        default:
            break
        }
    }

    @MainActor
    private func seedMeter(_ recording: RecordingModel) async {
        for sample in [0.12, 0.24, 0.59, 0.81, 0.36, 0.16, 0.53, 0.42] {
            lock.withLock { sampleLevel = sample }
            await recording.tick()
        }
    }

    public func read(_ name: String) throws -> Data? { lock.withLock { files[name] } }
    public func write(_ data: Data, name: String) throws { lock.withLock { files[name] = data } }
    public func remove(_ name: String) throws { lock.withLock { files[name] = nil } }
    public func list() throws -> [String] { lock.withLock { files.keys.sorted() } }

    public func next() -> UUID {
        lock.withLock {
            serial += 1
            let suffix = String(serial & 0xffffffffffff, radix: 16)
            return UUID(uuidString: "00000000-0000-4000-8000-" + String(repeating: "0", count: 12 - suffix.count) + suffix)!
        }
    }

    public func loadToken() -> String? { "example-audit" }
    public func saveToken(_ token: String) {}
    public func deleteToken() {}
    public func loadBaseURL() -> String? { "https://example.invalid" }
    public func saveBaseURL(_ url: String) {}
    public func clearBaseURL() {}
    public func start(clientId: String) async throws {
        if stop.id == "permission-recovery" { throw RecorderError.permissionDenied }
    }
    public func stop() async throws -> Data { Data([1]) }
    public func cancel() async {}
    public func transcribe(_ audio: Data, vocabulary: [String]) async throws -> String { "Example recording" }
    public func recordingStarted() {}
    public func recordingSaved() {}
    public func begin() {}
    public func end() {}
    public func requestPermission() async -> Bool { false }
    public func schedule(_ request: NotificationRequest) async {}
    public func remove(identifier: String) async {}

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        switch (request.method, request.url.path) {
        case ("GET", "/v1/health"): HTTPResponse(status: 200, body: Data(#"{"ok":true}"#.utf8))
        case ("GET", "/v1/snapshot"): HTTPResponse(status: 200, body: snapshot)
        case ("POST", "/v1/chat"): HTTPResponse(status: 200, body: Data(#"{"reply":"Paris."}"#.utf8))
        default: HTTPResponse(status: 503)
        }
    }

    /// Opens a Quick Chat over this fixture's fixed fake transport and asks the audit question once.
    @MainActor
    public func chatSession() async -> ChatSessionModel {
        let session = ChatSessionModel(transport: self, pairing: Pairing(tokenStore: self, settings: self))
        session.open()
        await session.send(text: ChatSheetScreen.seedQuestion)
        return session
    }

    private var snapshot: Data {
        let fields = stop.id == "xl-bottom-bar" ? unreadableFields : todayFields
        return Data("""
            {"api":2,"today":"2026-11-17","timezone":"UTC","generated_at":"2026-11-17T12:00:00Z",\(fields)}
            """.utf8)
    }

    private var todayFields: String {
        let notes = String(repeating: "Review sample notes and prepare the next demo. ", count: 8)
        return """
            "tasks":[
              {"handle":"sample-short","rev":"r1","text":"\(notes.prefix(100))","state":"open","when":{"kind":"today"}},
              {"handle":"sample-long","rev":"r1","text":"\(notes.prefix(350))","state":"open","when":{"kind":"today"}},
              {"handle":"sample-later","rev":"r1","text":"Check the supply list","state":"open","when":{"kind":"later"}}],
            "waiting":[{"handle":"sample-waiting","rev":"r1","text":"Await sample delivery","state":"open"}],
            "candidates":[{"handle":"sample-idea","rev":"r1","text":"Plan a demo","state":"open"}]
            """
    }

    private var unreadableFields: String {
        let rows = (1...1234).map { #"{"file":"Synthetic import","line":\#($0)}"# }.joined(separator: ",")
        return #""unreadable":[\#(rows)]"#
    }
}
