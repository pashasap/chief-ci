import Foundation
import Observation

public struct TranscriberAvailability: Equatable, Sendable {
    public var speech: Bool
    public var dictation: Bool

    public init(speech: Bool, dictation: Bool) {
        self.speech = speech
        self.dictation = dictation
    }
}

public struct SettingsServices: Sendable {
    public var files: any FileStore
    public var clock: any Clock
    public var timeZone: TimeZone
    public var transcribers: TranscriberAvailability

    public init(
        files: any FileStore, clock: any Clock, timeZone: TimeZone, transcribers: TranscriberAvailability
    ) {
        self.files = files
        self.clock = clock
        self.timeZone = timeZone
        self.transcribers = transcribers
    }
}

private struct HealthAnswer: Decodable {
    var ok: Bool
}

@MainActor
@Observable
public final class SettingsModel {
    public private(set) var message: String?
    /// The outcome of the last Check server.
    public private(set) var checkResult: String?
    /// Set by the app target; shown in the copied diagnostics.
    public var appVersion = "unknown"
    private var answeredAt: Date?
    private var revision = 0
    /// Set by the app target; nil leaves the Reminders section off.
    public var reminders: ReminderModel?
    @ObservationIgnored public var afterUnpair: (@MainActor () -> Void)?
    @ObservationIgnored public var afterPairing: (@MainActor () async -> Void)?

    @ObservationIgnored private let transport: any HTTPTransport
    @ObservationIgnored private let pairing: Pairing
    @ObservationIgnored private let pairingModel: PairingModel
    @ObservationIgnored let services: SettingsServices
    @ObservationIgnored let diagnostics: DiagnosticsStore

    public init(
        transport: any HTTPTransport, tokenStore: any TokenStore, settings: any SettingsFile,
        services: SettingsServices
    ) {
        self.transport = transport
        self.pairing = Pairing(tokenStore: tokenStore, settings: settings)
        self.pairingModel = PairingModel(transport: transport, tokenStore: tokenStore, settings: settings)
        self.services = services
        self.diagnostics = DiagnosticsStore(files: services.files, clock: services.clock)
    }

    var timeZone: TimeZone { services.timeZone }

    public var isPaired: Bool {
        _ = revision
        return pairing.isPaired
    }

    /// Status entries (label and value apart), read live from the stores.
    public var entries: [SettingsEntry] {
        let cached = SnapshotCache(files: services.files).load()
        let outbox = OutboxStore(files: services.files).records().count
        return [
            SettingsEntry(label: "Pairing", value: isPaired ? "Paired" : "Not paired"),
            SettingsEntry(label: "Server address", value: addressRow),
            SettingsEntry(
                label: "Server answered",
                value: answeredAt.map { clockText($0) } ?? "Server has not answered"),
            SettingsEntry(
                label: "Last snapshot",
                value: cached.map { clockText($0.fetchedAt) } ?? "No snapshot yet"),
            SettingsEntry(label: "Waiting in outbox", value: String(outbox)),
            SettingsEntry(label: "Where", value: "On this iPhone"),
            SettingsEntry(label: "Language", value: "English (US)"),
            SettingsEntry(label: "Speech model", value: Self.word(services.transcribers.speech)),
            SettingsEntry(
                label: "Dictation model", value: Self.word(services.transcribers.dictation)),
        ]
    }

    /// Always ends in "Server answered", "Not paired" or "Server has not answered".
    public func opened() async { await checkServer() }

    public func checkServer() async {
        let result = await probe()
        checkResult = result
        if result != Self.answeredText { diagnostics.recordProblem(result) }
    }

    private func probe() async -> String {
        guard let base = pairing.baseURL, let token = pairing.token,
            let url = URL(string: base + "/v1/health")
        else { return Self.notPairedText }
        let request = HTTPRequest(method: "GET", url: url, headers: ["Authorization": "Bearer " + token])
        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch {
            return Self.silentText
        }
        diagnostics.recordAnswer(status: response.status)
        if response.status == 401 { return Self.notPairedText }
        guard response.status == 200, Self.isHealthy(response.body) else { return Self.silentText }
        answeredAt = services.clock.now
        return Self.answeredText
    }

    private static func isHealthy(_ body: Data) -> Bool {
        do {
            return try JSONDecoder().decode(HealthAnswer.self, from: body).ok
        } catch {
            return false
        }
    }

    static let answeredText = "Server answered"
    static let notPairedText = "Not paired"
    static let silentText = "Server has not answered"

    public func pasteLink(_ text: String) async {
        await pairingModel.pair(link: text)
        message = pairingModel.message
        revision += 1
        if isPaired { await afterPairing?() }
    }

    /// Removes the token, the server address and the snapshot cache. Outbox records stay.
    public func unpair() {
        pairing.clear()
        message = nil
        do {
            try services.files.remove(SnapshotCache.fileName)
        } catch {
            message = "The saved data could not be removed"
        }
        answeredAt = nil
        checkResult = nil
        revision += 1
        afterUnpair?()
    }

    private var addressRow: String {
        guard let base = pairing.baseURL, let parts = URLComponents(string: base),
            let scheme = parts.scheme, let host = parts.host
        else { return "No server address" }
        return scheme + "://" + host
    }

    func clockText(_ date: Date) -> String {
        InboxRows.clockText(date, in: services.timeZone)
    }

    private static func word(_ available: Bool) -> String { available ? "Available" : "Not available" }
}
