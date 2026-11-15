import Foundation

public struct Snapshot: Codable, Equatable, Sendable {
    public var api: Int
    public var generatedAt: String?
    public var today: String?
    public var timezone: String?
    public var captures: [Capture]
    public var tasks: [TaskItem]
    public var notes: [Note]
    public var waiting: [Waiting]
    public var candidates: [Candidate]
    public var proposals: [Proposal]
    public var questions: [Question]
    public var results: [Result]
    public var settings: SnapshotSettings?
    public var unreadable: [Unreadable]
    public var brief: SnapshotBrief?
    public var health: SnapshotHealth?
    public var actions: SnapshotActions?

    enum CodingKeys: String, CodingKey {
        case api, today, timezone, captures, tasks, notes, waiting, candidates
        case proposals, questions, results, settings, unreadable, brief, health, actions
        case generatedAt = "generated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let reader = LenientReader(container: c, sink: decoder.userInfo[SkipSink.key] as? SkipSink)
        api = try c.decode(Int.self, forKey: .api)
        generatedAt = try c.decodeIfPresent(String.self, forKey: .generatedAt)
        today = try c.decodeIfPresent(String.self, forKey: .today)
        timezone = try c.decodeIfPresent(String.self, forKey: .timezone)
        captures = reader.list(Capture.self, .captures)
        tasks = reader.list(TaskItem.self, .tasks)
        notes = reader.list(Note.self, .notes)
        waiting = reader.list(Waiting.self, .waiting)
        candidates = reader.list(Candidate.self, .candidates)
        proposals = reader.list(Proposal.self, .proposals)
        questions = reader.list(Question.self, .questions)
        results = reader.list(Result.self, .results)
        settings = reader.value(SnapshotSettings.self, .settings)
        unreadable = reader.list(Unreadable.self, .unreadable)
        brief = reader.value(SnapshotBrief.self, .brief)
        health = reader.value(SnapshotHealth.self, .health)
        actions = reader.value(SnapshotActions.self, .actions)
    }
}
