import Foundation

public struct SnapshotBrief: Codable, Equatable, Sendable {
    public var recorded: Bool
    public var lines: [String]
    public var date: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decodeIfPresent(String.self, forKey: .date)
        recorded = try c.decodeIfPresent(Bool.self, forKey: .recorded) ?? false
        lines = try c.decodeIfPresent([String].self, forKey: .lines) ?? []
    }

    enum CodingKeys: String, CodingKey { case recorded, lines, date }
}

public struct SnapshotLastResult: Codable, Equatable, Sendable {
    public var handle: String
    public var date: String?
}

public struct SnapshotHealth: Codable, Equatable, Sendable {
    public var briefRanToday: Bool?
    public var lastResult: SnapshotLastResult?
    public var boardDate: String?

    enum CodingKeys: String, CodingKey {
        case boardDate = "board_date"
        case briefRanToday = "brief_ran_today"
        case lastResult = "last_result"
    }
}

public struct SnapshotActions: Codable, Equatable, Sendable {
    public var queued: Int?
    public var running: Int?
    public var blocked: Int?
    public var failed: Int?
}
