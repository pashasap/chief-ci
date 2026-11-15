import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

/// One user action on one item, as the contract sends it. `rev` is the item's opaque rev string from the snapshot.
public struct Command: Codable, Equatable, Sendable {
    public var id: String
    public var type: String
    public var handle: String
    public var rev: String
    public var args: [String: JSONValue]

    /// The wire `rev`; kept as a name older tests and callers read.
    public var revText: String? { rev }
}

public enum CommandBuilder {
    /// Builds a command with a fresh lowercase UUID. Callers pass the rev string of the item in the current
    /// snapshot; no caller builds a command for an item without one (see `DecisionModel.send`).
    public static func make(type: String, handle: String, rev: String, args: [String: JSONValue]) -> Command {
        Command(id: UUID().uuidString.lowercased(), type: type, handle: handle, rev: rev, args: args)
    }
}
