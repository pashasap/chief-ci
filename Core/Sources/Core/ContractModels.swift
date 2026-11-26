import Foundation

/// Contract models. Decoding ignores unknown fields (Codable's default) and tolerates absent optional fields.

public struct When: Codable, Equatable, Sendable {
    public var kind: String
    public var date: String?
}

public struct Item: Codable, Equatable, Sendable {
    public var handle: String
    public var kind: String
    public var text: String
    public var state: String?
}

public struct Capture: Codable, Equatable, Sendable {
    public var id: String
    public var date: String?
    public var time: String?
    public var source: String?
    public var clientId: String?
    public var text: String
    public var status: String
    public var statusNote: String?
    public var items: [Item]

    enum CodingKeys: String, CodingKey {
        case id, date, time, source, text, status, items
        case clientId = "client_id"
        case statusNote = "status_note"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        date = try c.decodeIfPresent(String.self, forKey: .date)
        time = try c.decodeIfPresent(String.self, forKey: .time)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        clientId = try c.decodeIfPresent(String.self, forKey: .clientId)
        text = try c.decode(String.self, forKey: .text)
        status = try c.decode(String.self, forKey: .status)
        statusNote = try c.decodeIfPresent(String.self, forKey: .statusNote)
        items = try c.decodeIfPresent([Item].self, forKey: .items) ?? []
    }
}

/// Kit's pick for a task: shown in Today or parked in Later. A missing, null or unknown value is no pick.
public enum TaskPick: String, Codable, Equatable, Sendable {
    case today, later

    public init?(lenient value: String?) {
        guard let value else { return nil }
        self.init(rawValue: value)
    }
}

public struct TaskItem: Codable, Equatable, Sendable {
    public var handle: String
    public var rev: String?
    public var text: String
    public var state: String
    public var when: When?
    public var note: String?
    public var capture: String?
    public var pick: TaskPick?

    enum CodingKeys: String, CodingKey {
        case handle, rev, text, state, when, note, capture, pick
    }
}

extension TaskItem {
    /// Lenient: a missing key, null or unknown value decodes as no pick.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        handle = try c.decode(String.self, forKey: .handle)
        rev = try c.decodeIfPresent(String.self, forKey: .rev)
        text = try c.decode(String.self, forKey: .text)
        state = try c.decode(String.self, forKey: .state)
        when = try c.decodeIfPresent(When.self, forKey: .when)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        capture = try c.decodeIfPresent(String.self, forKey: .capture)
        pick = TaskPick(lenient: try c.decodeIfPresent(String.self, forKey: .pick))
    }
}

public struct Note: Codable, Equatable, Sendable {
    public var handle: String
    public var rev: String?
    public var text: String
    public var state: String?
    public var capture: String?
    /// "idea" for a note the server filed as an idea; absent for a plain note.
    public var kind: String?
}

public struct Waiting: Codable, Equatable, Sendable {
    public var handle: String
    public var rev: String?
    public var text: String
    public var state: String?
    public var since: String?
}

/// A candidate's decision; a missing or unknown value is open, so an older snapshot offers it.
public enum CandidateDecision: String, Codable, Equatable, Sendable {
    case open, started, kept, dropped

    public init(lenient value: String?) {
        guard let value, let decision = Self(rawValue: value) else {
            self = .open
            return
        }
        self = decision
    }
}

public struct Candidate: Codable, Equatable, Sendable {
    public var handle: String
    public var rev: String?
    public var text: String
    public var state: String?
    public var note: String?
    /// The action handle of the research already queued for this candidate, when the server identified one.
    public var research: String?
    public var decision: CandidateDecision

    enum CodingKeys: String, CodingKey {
        case handle, rev, text, state, note, research, decision
    }

    /// True while the snapshot names a research action; then no second one may be requested.
    public var hasResearch: Bool {
        !(research ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension Candidate {
    /// Lenient: a missing or unknown decision decodes as open.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        handle = try c.decode(String.self, forKey: .handle)
        rev = try c.decodeIfPresent(String.self, forKey: .rev)
        text = try c.decode(String.self, forKey: .text)
        state = try c.decodeIfPresent(String.self, forKey: .state)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        research = try c.decodeIfPresent(String.self, forKey: .research)
        decision = CandidateDecision(lenient: try c.decodeIfPresent(String.self, forKey: .decision))
    }
}

public struct Proposal: Codable, Equatable, Sendable {
    public var handle: String
    public var rev: String?
    public var would: String
    public var because: String?
    public var capture: String?
    public var state: String
    public var action: String?

    /// "Queued as <action>" for an approved suggestion that has an action, otherwise nil.
    public var queuedLine: String? {
        guard state == "approved", let action else { return nil }
        return "Queued as " + action
    }
}

public struct Question: Codable, Equatable, Sendable {
    public var handle: String
    public var rev: String?
    public var question: String
    public var options: [String]
    public var about: String?
    public var capture: String?
    public var state: String
    public var answer: String?

    enum CodingKeys: String, CodingKey {
        case handle, rev, question, options, about, capture, state, answer
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        handle = try c.decode(String.self, forKey: .handle)
        rev = try c.decodeIfPresent(String.self, forKey: .rev)
        question = try c.decode(String.self, forKey: .question)
        options = try c.decodeIfPresent([String].self, forKey: .options) ?? []
        about = try c.decodeIfPresent(String.self, forKey: .about)
        capture = try c.decodeIfPresent(String.self, forKey: .capture)
        state = try c.decode(String.self, forKey: .state)
        answer = try c.decodeIfPresent(String.self, forKey: .answer)
    }
}

public struct Result: Codable, Equatable, Sendable {
    public var handle: String
    public var title: String?
    public var answer: String?
    public var kind: String?
    public var capture: String?
    public var state: String?
    public var date: String?
    public var asked: String?
    public var hasDraft: Bool?

    enum CodingKeys: String, CodingKey {
        case handle, title, answer, kind, capture, state, date, asked
        case hasDraft = "has_draft"
    }
}

public struct Unreadable: Codable, Equatable, Sendable {
    public var file: String
    public var line: Int
    public var text: String?
}

public struct ErrorDetail: Codable, Equatable, Sendable {
    public var code: String
    public var message: String
}

public struct ErrorBody: Codable, Equatable, Sendable {
    public var error: ErrorDetail
}

public struct SnapshotSettings: Codable, Equatable, Sendable {
    public var briefTime: String?
    public var vocabulary: [String]?

    enum CodingKeys: String, CodingKey {
        case briefTime = "brief_time"
        case vocabulary
    }
}
