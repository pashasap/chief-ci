import Foundation
import Observation

private enum Outcome: Equatable {
    case done
    case unauthorized
    case failed
    /// The server refused the capture for good (400, 413, 422), with its message.
    case refused(String)
}

private struct CapturePost: Encodable {
    var clientId: String
    var recordedAt: Date
    var kind: String
    var durationS: Double
    var text: String
    var transcriber: String
    var locale: String
    var hasAudio: Bool
    var alt: OutboxAlt?

    enum CodingKeys: String, CodingKey {
        case alt
        case clientId = "client_id"
        case recordedAt = "recorded_at"
        case kind, text, transcriber, locale
        case durationS = "duration_s"
        case hasAudio = "has_audio"
    }

    init(_ record: OutboxRecord) {
        clientId = record.clientId
        recordedAt = record.recordedAt
        kind = record.kind
        durationS = record.durationS
        text = record.text
        transcriber = record.transcriber
        locale = record.locale
        hasAudio = record.hasAudio
        alt = record.alt
    }
}

private struct Auth {
    var base: String
    var token: String

    func request(_ method: String, _ path: String, _ type: String, _ body: Data) -> HTTPRequest? {
        guard let url = URL(string: base + path) else { return nil }
        let headers = ["Authorization": "Bearer " + token, "Content-Type": type]
        return HTTPRequest(method: method, url: url, headers: headers, body: body)
    }
}

@MainActor
@Observable
public final class UploadEngine {
    public private(set) var status = "Idle"
    public private(set) var notices: [String] = []
    /// The capture being sent right now, if any.
    public private(set) var sendingId: String?
    public private(set) var confirmedIds: Set<String> = []
    @ObservationIgnored public var afterRun: (@MainActor () async -> Void)?
    /// The earliest time a failed capture may be tried again; nil when nothing waits for a retry.
    public private(set) var nextRetry: Date?
    /// The capture being recorded. Its record has no audio yet, so the engine leaves it alone.
    public var recordingId: String?
    /// Notices about captures removed because their audio was missing.
    public private(set) var removedNotices: [String] = []

    public static let sendingText = "Sending"
    public static let notPairedText = "Not paired. Pair in Settings to send it."
    public static let retryNowLabel = "Retry now"
    public static let missingAudioNotice = "A recording had no audio file. It was removed."

    /// Why a capture still on this iPhone has not left yet, or nil when nothing explains it.
    public func waitLine(for record: OutboxRecord) -> String? {
        if record.refusal != nil { return nil }
        if sendingId == record.clientId { return Self.sendingText }
        if !pairing.isPaired || status == "Not paired" { return Self.notPairedText }
        if let retry = record.nextRetry {
            if retry > clock.now { return "Waiting to retry at " + InboxRows.clockText(retry, in: .current) }
            return "Did not go through. Trying again."
        }
        return nil
    }

    /// True when "Retry now" makes sense for this record: it failed before and is not being sent.
    public func offersRetryNow(for record: OutboxRecord) -> Bool {
        record.refusal == nil && record.nextRetry != nil && sendingId != record.clientId && pairing.isPaired && status != "Not paired"
    }

    /// Sends every waiting capture now, ignoring the retry times.
    public func retryNow() async {
        for var record in store.records() where record.nextRetry != nil && record.refusal == nil {
            record.nextRetry = nil
            persist(record)
        }
        await run()
    }
    /// Kit's line after the server confirmed a capture, and until when it shows.
    private var reached: (line: String, until: Date)?
    @ObservationIgnored private let voice = KitVoiceCounter()

    /// Kit's capture line for `KitVoice.barSeconds` after the server confirmed a capture.
    public var kitBar: String? {
        guard let reached, clock.now < reached.until else { return nil }
        return reached.line
    }

    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var runAgain = false
    @ObservationIgnored private let store: OutboxStore
    @ObservationIgnored private let transport: any HTTPTransport
    @ObservationIgnored private let pairing: Pairing
    @ObservationIgnored private let clock: any Clock

    public init(store: OutboxStore, transport: any HTTPTransport, pairing: Pairing, clock: any Clock) {
        self.store = store
        self.transport = transport
        self.pairing = pairing
        self.clock = clock
    }

    /// Serializes sends. A trigger during a send requests another pass so new captures are not missed.
    public func run() async {
        if isRunning { runAgain = true; return }
        isRunning = true
        repeat {
            runAgain = false
            await sendWaiting()
        } while runAgain
        isRunning = false
        await afterRun?()
    }

    private func sendWaiting() async {
        defer {
            sendingId = nil
            nextRetry = store.records()
                .filter { $0.refusal == nil && $0.clientId != recordingId }
                .compactMap(\.nextRetry).min()
        }
        for record in store.records() where record.clientId != recordingId && record.hasAudio && record.stage == .audioPending {
            if store.audioIsMissing(clientId: record.clientId) {
                store.remove(clientId: record.clientId)
                removedNotices.append(Self.missingAudioNotice)
            }
        }
        let records = store.records()
        notices = store.notices
        guard let base = pairing.baseURL, let token = pairing.token else {
            status = "Not paired"
            return
        }
        let auth = Auth(base: base, token: token)
        status = "Up to date"
        for record in records where record.clientId != recordingId {
            if record.stage == .confirmed {
                store.remove(clientId: record.clientId)
                continue
            }
            if record.refusal != nil { continue }
            if let retry = record.nextRetry, retry > clock.now { continue }
            sendingId = record.clientId
            let outcome = await upload(record, auth)
            sendingId = nil
            if outcome == .unauthorized {
                status = "Not paired"
                return
            }
            if outcome == .failed { status = "Waiting to retry" }
        }
    }

    private func upload(_ start: OutboxRecord, _ auth: Auth) async -> Outcome {
        var record = start
        if record.stage == .audioPending && record.hasAudio {
            guard let audio = store.audio(clientId: record.clientId) else {
                // The file is there and cannot be read right now: keep the capture and try again later.
                guard store.audioIsMissing(clientId: record.clientId) else { return fail(.failed, record) }
                // A recording killed before Stop: the record exists, the audio never did. Nothing can be sent.
                store.remove(clientId: record.clientId)
                notices.append("Audio file missing for capture \(record.clientId)")
                removedNotices.append(Self.missingAudioNotice)
                return .done
            }
            let path = "/v1/captures/" + record.clientId + "/audio"
            let outcome = await send(auth.request("PUT", path, "audio/mp4", audio))
            if outcome != .done { return fail(outcome, record) }
        }
        if record.stage == .audioPending {
            record.stage = .recordPending
            persist(record)
        }
        let body: Data
        do {
            body = try Self.encoder().encode(CapturePost(record))
        } catch {
            notices.append("Could not prepare capture \(record.clientId) for sending")
            return .failed
        }
        let outcome = await send(auth.request("POST", "/v1/captures", "application/json", body))
        if outcome != .done { return fail(outcome, record) }
        record.stage = .confirmed
        persist(record)
        store.remove(clientId: record.clientId)
        confirmedIds.insert(record.clientId)
        reached = (voice.next(.captureReached), clock.now.addingTimeInterval(KitVoice.barSeconds))
        return .done
    }

    private func fail(_ outcome: Outcome, _ record: OutboxRecord) -> Outcome {
        var changed = record
        switch outcome {
        case .refused(let message):
            changed.refusal = message
        case .failed:
            changed.attempt += 1
            changed.nextRetry = clock.now.addingTimeInterval(Backoff.delay(attempt: changed.attempt))
        case .done, .unauthorized:
            return outcome
        }
        persist(changed)
        return outcome
    }

    private func persist(_ record: OutboxRecord) {
        do {
            try store.save(record)
        } catch {
            notices.append("Could not save capture \(record.clientId) on this iPhone")
        }
    }

    private func send(_ request: HTTPRequest?) async -> Outcome {
        guard let request else { return .failed }
        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch {
            return .failed
        }
        switch response.status {
        case 401: return .unauthorized
        case 200..<300: return .done
        case 400, 413, 422: return .refused(Self.message(response.body))
        default: return .failed
        }
    }

    private static func message(_ body: Data) -> String {
        do {
            return try JSONDecoder().decode(ErrorBody.self, from: body).error.message
        } catch {
            return "The server refused this capture"
        }
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
