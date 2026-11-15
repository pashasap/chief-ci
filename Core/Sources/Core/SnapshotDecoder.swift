import Foundation

/// One list element (or section) of the snapshot that could not be decoded.
public struct SkippedElement: Codable, Equatable, Sendable {
    public var listName: String
    public var reason: String

    public init(listName: String, reason: String) {
        self.listName = listName
        self.reason = reason
    }
}

public struct DecodedSnapshot: Equatable, Sendable {
    public var snapshot: Snapshot
    public var skipped: [SkippedElement]
}

/// Collects the skips of one decoding run. Passed through `JSONDecoder.userInfo`.
final class SkipSink: @unchecked Sendable {
    static let key = CodingUserInfoKey(rawValue: "chief.skipSink")!
    private(set) var items: [SkippedElement] = []

    func add(_ listName: String, _ error: Error) {
        items.append(SkippedElement(listName: listName, reason: Self.reason(error)))
    }

    static func reason(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else { return String(describing: error) }
        switch decoding {
        case .keyNotFound(let key, _): return "missing key " + key.stringValue
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            let path = context.codingPath.map(\.stringValue).filter { !$0.isEmpty }.joined(separator: ".")
            let text = context.debugDescription.isEmpty ? "unreadable value" : context.debugDescription
            return path.isEmpty ? text : path + ": " + text
        @unknown default: return "unreadable element"
        }
    }
}

/// Decodes a snapshot list element by element: a bad element is skipped and reported to the sink.
struct LenientReader {
    let container: KeyedDecodingContainer<Snapshot.CodingKeys>
    let sink: SkipSink?

    private struct Discard: Decodable {}

    func list<T: Decodable>(_ type: T.Type, _ key: Snapshot.CodingKeys) -> [T] {
        guard container.contains(key), (try? container.decodeNil(forKey: key)) != true else { return [] }
        var out: [T] = []
        do {
            var items = try container.nestedUnkeyedContainer(forKey: key)
            while !items.isAtEnd {
                do {
                    out.append(try items.decode(T.self))
                } catch {
                    sink?.add(key.stringValue, error)
                    _ = try items.decode(Discard.self)
                }
            }
        } catch {
            sink?.add(key.stringValue, error)
        }
        return out
    }

    func value<T: Decodable>(_ type: T.Type, _ key: Snapshot.CodingKeys) -> T? {
        do {
            return try container.decodeIfPresent(T.self, forKey: key)
        } catch {
            sink?.add(key.stringValue, error)
            return nil
        }
    }
}

public enum SnapshotDecoder {
    /// Throws only when the top level is unreadable (not JSON, no `api`). A bad element never throws.
    public static func decode(_ data: Data) throws -> DecodedSnapshot {
        let sink = SkipSink()
        let decoder = JSONDecoder()
        decoder.userInfo[SkipSink.key] = sink
        let snapshot = try decoder.decode(Snapshot.self, from: data)
        return DecodedSnapshot(snapshot: snapshot, skipped: sink.items)
    }
}
