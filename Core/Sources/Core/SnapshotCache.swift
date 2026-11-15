import Foundation

public struct CachedSnapshot: Equatable, Sendable {
    public var snapshot: Snapshot
    public var fetchedAt: Date
    public var etag: String?
    /// Elements of the last fetch that could not be decoded.
    public var skipped: [SkippedElement]

    public init(snapshot: Snapshot, fetchedAt: Date, etag: String?, skipped: [SkippedElement] = []) {
        self.snapshot = snapshot
        self.fetchedAt = fetchedAt
        self.etag = etag
        self.skipped = skipped
    }
}

private struct CacheEnvelope: Codable {
    var version: Int
    var fetchedAt: Date
    var etag: String?
    var snapshot: Snapshot
    var skipped: [SkippedElement]?
}

private struct CacheVersionProbe: Decodable {
    var version: Int
}

/// Versioned, atomically written file holding the last snapshot with its fetch time and ETag.
/// An unusable file is never removed: `load()` returns nil and sets `notice`.
public final class SnapshotCache: @unchecked Sendable {
    public static let currentVersion = 1
    public static let fileName = "snapshot-cache.json"

    private let files: any FileStore

    public init(files: any FileStore) {
        self.files = files
    }

    /// Non-nil when the file on disk exists but cannot be used.
    public var notice: String? { inspect().notice }

    public func save(_ cached: CachedSnapshot) throws {
        let envelope = CacheEnvelope(
            version: Self.currentVersion, fetchedAt: cached.fetchedAt, etag: cached.etag,
            snapshot: cached.snapshot, skipped: cached.skipped)
        try files.write(JSONEncoder().encode(envelope), name: Self.fileName)
    }

    public func load() -> CachedSnapshot? { inspect().cached }

    private func inspect() -> (cached: CachedSnapshot?, notice: String?) {
        let damaged = "The saved data is damaged and was ignored"
        let data: Data
        do {
            guard let read = try files.read(Self.fileName) else { return (nil, nil) }
            data = read
        } catch {
            return (nil, "The saved data could not be read")
        }
        guard let probe = try? JSONDecoder().decode(CacheVersionProbe.self, from: data) else {
            return (nil, damaged)
        }
        if probe.version > Self.currentVersion {
            return (nil, "The saved data was written by a newer version and was ignored")
        }
        guard let envelope = try? JSONDecoder().decode(CacheEnvelope.self, from: data) else {
            return (nil, damaged)
        }
        let cached = CachedSnapshot(
            snapshot: envelope.snapshot, fetchedAt: envelope.fetchedAt, etag: envelope.etag,
            skipped: envelope.skipped ?? [])
        return (cached, nil)
    }
}
