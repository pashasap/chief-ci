import Foundation
import Observation

/// Folder of named files; the real one lives in the app target, tests use an in-memory fake.
public protocol FileStore: Sendable {
    func read(_ name: String) throws -> Data?
    /// Atomically replaces the complete contents of a named file.
    func write(_ data: Data, name: String) throws
    func remove(_ name: String) throws
    func list() throws -> [String]
}

public protocol Clock: Sendable {
    var now: Date { get }
}

public protocol UUIDSource: Sendable {
    func next() -> UUID
}

public enum UploadStage: String, Codable, Equatable, Sendable {
    case audioPending
    case recordPending
    case confirmed
}

public enum Backoff {
    /// 2, 4, 8, 16, 32 then 60 seconds for attempt 1, 2, 3, ...
    public static func delay(attempt: Int) -> TimeInterval {
        let exponent = min(max(attempt, 1), 10)
        return min(60, TimeInterval(1 << exponent))
    }
}

/// Second transcript of the same audio, sent as "alt": {transcriber, text}.
public struct OutboxAlt: Codable, Equatable, Sendable {
    public var transcriber: String
    public var text: String

    public init(transcriber: String, text: String) {
        self.transcriber = transcriber
        self.text = text
    }
}

public struct OutboxRecord: Codable, Equatable, Sendable {
    public var clientId: String
    public var recordedAt: Date
    public var kind: String
    public var durationS: Double
    public var text: String
    public var transcriber: String
    public var locale: String
    public var hasAudio: Bool
    public var stage: UploadStage
    public var attempt: Int
    public var nextRetry: Date?
    public var alt: OutboxAlt?
    /// The server's message when it refused this capture (400, 413, 422). Such a record is never sent again.
    public var refusal: String?

    enum CodingKeys: String, CodingKey {
        case alt, refusal
        case clientId = "client_id"
        case recordedAt = "recorded_at"
        case kind
        case durationS = "duration_s"
        case text
        case transcriber
        case locale
        case hasAudio = "has_audio"
        case stage
        case attempt
        case nextRetry = "next_retry"
    }

    public static func voice(clientId: String, recordedAt: Date, durationS: Double) -> OutboxRecord {
        OutboxRecord(
            clientId: clientId, recordedAt: recordedAt, kind: "voice", durationS: durationS,
            text: "", transcriber: "none", locale: "", hasAudio: true, stage: .audioPending,
            attempt: 0, nextRetry: nil)
    }

    public static func typed(clientId: String, recordedAt: Date, text: String) -> OutboxRecord {
        OutboxRecord(
            clientId: clientId, recordedAt: recordedAt, kind: "typed", durationS: 0,
            text: text, transcriber: "none", locale: "", hasAudio: false, stage: .recordPending,
            attempt: 0, nextRetry: nil)
    }
}

private enum VersionKey: String, CodingKey {
    case version
}

private struct VersionProbe: Decodable {
    var version: Int
}

private struct Envelope: Encodable {
    var record: OutboxRecord

    func encode(to encoder: any Encoder) throws {
        try record.encode(to: encoder)
        var container = encoder.container(keyedBy: VersionKey.self)
        try container.encode(OutboxStore.currentVersion, forKey: .version)
    }
}

@Observable
public final class OutboxStore {
    public static let currentVersion = 1

    @ObservationIgnored private let files: any FileStore
    @ObservationIgnored public private(set) var notices: [String] = []
    public private(set) var revision = 0

    /// Failed reads also block capture so an unreadable outbox is not treated as empty.
    public var hasPendingCapture: Bool {
        _ = revision
        let pending = !records().isEmpty
        return pending || !notices.isEmpty
    }

    public init(files: any FileStore) {
        self.files = files
    }

    public func save(_ record: OutboxRecord) throws {
        let data = try JSONEncoder().encode(Envelope(record: record))
        try files.write(data, name: Self.recordName(record.clientId))
        revision += 1
    }

    func unsentDraft() throws -> CaptureDraft? {
        guard let draft = try CaptureDraft.read(from: files) else { return nil }
        if try files.read(Self.recordName(draft.id)) != nil {
            try discardDraft()
            return nil
        }
        return draft
    }

    func saveDraft(_ draft: CaptureDraft) throws {
        try files.write(JSONEncoder().encode(draft), name: CaptureDraft.fileName)
    }

    func discardDraft() throws {
        try files.remove(CaptureDraft.fileName)
    }

    /// Do not let delivery erase the outbox evidence of a draft commit before cleanup.
    func clearDraft(committedId: String) throws {
        if try CaptureDraft.read(from: files)?.id == committedId { try discardDraft() }
    }

    public func saveAudio(_ data: Data, clientId: String) throws {
        try files.write(data, name: Self.audioName(clientId))
    }

    /// True only when the file is known to be absent. A file that cannot be read right now is not missing.
    public func audioIsMissing(clientId: String) -> Bool {
        do {
            return try files.read(Self.audioName(clientId)) == nil
        } catch {
            return false
        }
    }

    public func audio(clientId: String) -> Data? {
        do {
            return try files.read(Self.audioName(clientId))
        } catch {
            notices.append("Could not read the audio of capture \(clientId)")
            return nil
        }
    }

    /// Readable records, oldest first. Unreadable files are skipped, kept, and reported in `notices`.
    public func records() -> [OutboxRecord] {
        notices = []
        let names: [String]
        do {
            names = try files.list()
        } catch {
            notices = ["The outbox folder could not be read"]
            return []
        }
        var found: [OutboxRecord] = []
        for name in names where name.hasSuffix(".json") && name != SnapshotCache.fileName {
            if let record = load(name) { found.append(record) }
        }
        return found.sorted { ($0.recordedAt, $0.clientId) < ($1.recordedAt, $1.clientId) }
    }

    public func remove(clientId: String) {
        defer { revision += 1 }
        for name in [Self.recordName(clientId), Self.audioName(clientId)] {
            do {
                try files.remove(name)
            } catch {
                notices.append("Could not remove \(name)")
            }
        }
    }

    private func load(_ name: String) -> OutboxRecord? {
        let data: Data
        do {
            guard let read = try files.read(name) else { return nil }
            data = read
        } catch {
            notices.append("Could not read \(name)")
            return nil
        }
        guard let probe = try? JSONDecoder().decode(VersionProbe.self, from: data),
            let record = try? JSONDecoder().decode(OutboxRecord.self, from: data)
        else {
            notices.append("Skipped unreadable capture file \(name)")
            return nil
        }
        if probe.version > Self.currentVersion {
            notices.append("Skipped \(name): it was written by a newer version")
            return nil
        }
        return record
    }

    private static func recordName(_ clientId: String) -> String { clientId + ".json" }
    private static func audioName(_ clientId: String) -> String { clientId + ".m4a" }
}
