import Foundation
import Observation

/// Local thumbs-up / thumbs-down framing signal for a task or suggestion tile.
public enum FramingSignal: String, Codable, Equatable, Sendable {
    case up
    case down

    public var badgeText: String {
        self == .up ? "👍" : "👎"
    }

    public var label: String {
        self == .up ? "Good Framing" : "Bad Framing"
    }
}

public struct FramingSignalEntry: Codable, Equatable, Sendable {
    public var signal: FramingSignal
    public var timestamp: Date
    public var snippet: String

    public init(signal: FramingSignal, timestamp: Date, snippet: String) {
        self.signal = signal
        self.timestamp = timestamp
        self.snippet = snippet
    }
}

private struct FramingFileStore: FileStore {
    let folder: URL

    init(folderName: String = "chief") {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.folder = base.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func read(_ name: String) throws -> Data? {
        let url = folder.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    func write(_ data: Data, name: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent(name), options: .atomic)
    }

    func remove(_ name: String) throws {
        let url = folder.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    func list() throws -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()) ?? []
    }
}

private struct SystemWallClock: Clock {
    var now: Date { Date() }
}

/// Atomically persists per-handle framing feedback (`👍` / `👎`) in Application Support.
@MainActor @Observable
public final class FramingSignalStore {
    public static let fileName = "framing-signals.json"
    public static let shared = FramingSignalStore()

    @ObservationIgnored private let files: any FileStore
    @ObservationIgnored private let clock: any Clock
    public private(set) var entries: [String: FramingSignalEntry] = [:]
    public private(set) var storageError: String?

    public init(files: (any FileStore)? = nil, clock: (any Clock)? = nil) {
        self.files = files ?? FramingFileStore()
        self.clock = clock ?? SystemWallClock()
        reload()
    }

    public func signal(for handle: String) -> FramingSignal? {
        entries[handle]?.signal
    }

    public func entry(for handle: String) -> FramingSignalEntry? {
        entries[handle]
    }

    public func record(_ signal: FramingSignal, for handle: String, snippet: String) {
        let trimmed = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        entries[handle] = FramingSignalEntry(signal: signal, timestamp: clock.now, snippet: trimmed)
        persist()
    }

    public func clear(handle: String) {
        entries.removeValue(forKey: handle)
        persist()
    }

    public func reload() {
        guard let data = try? files.read(Self.fileName) else {
            entries = [:]
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([String: FramingSignalEntry].self, from: data) {
            entries = decoded
            storageError = nil
        } else {
            entries = [:]
            storageError = "Framing signals file could not be decoded"
        }
    }

    public func exportSummary() -> String {
        guard !entries.isEmpty else { return "No framing signals recorded." }
        return entries.keys.sorted().compactMap { key -> String? in
            guard let entry = entries[key] else { return nil }
            return "\(key): \(entry.signal.badgeText) (\(entry.snippet))"
        }.joined(separator: "\n")
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(entries)
            try files.write(data, name: Self.fileName)
            storageError = nil
        } catch {
            storageError = "Framing signals could not be saved"
        }
    }
}
