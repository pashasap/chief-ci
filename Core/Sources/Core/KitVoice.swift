import Foundation

/// The moments Kit has a dry line for. Each line is shown only after the server confirmed the action.
public enum KitMoment: CaseIterable, Sendable {
    case captureReached, taskDone, suggestionApproved, suggestionRejected, changeSent, questionAnswered
    case waitingClosed, correctionAccepted

    /// The moment a confirmed command of `type` stands for, or nil when it has no line.
    static func confirming(_ type: String) -> KitMoment? {
        switch type {
        case "task.done": return .taskDone
        case "proposal.approve": return .suggestionApproved
        case "proposal.reject": return .suggestionRejected
        case "proposal.change": return .changeSent
        case "question.answer": return .questionAnswered
        case "waiting.close": return .waitingClosed
        case "item.reclassify", "item.remove", "item.correct": return .correctionAccepted
        default: return nil
        }
    }
}

/// Kit's lines, word for word, in order. The line used is the one at position n modulo the number of lines,
/// where n counts how often that moment has happened since the app started, beginning at 0.
public enum KitVoice {
    /// How long a line stays on screen.
    public static let barSeconds: TimeInterval = 3

    public static func lines(for moment: KitMoment) -> [String] {
        switch moment {
        case .captureReached: return ["On it.", "Leave it with me.", "Noted. Handling it.", "Already moving.", "Mine now."]
        case .taskDone: return ["Sorted.", "Ticked off.", "Done. Minimal drama.", "All quiet on that front."]
        case .suggestionApproved: return ["Consider it done.", "On it.", "Leave it with me."]
        case .suggestionRejected: return ["Struck off.", "Gone. No hard feelings."]
        case .changeSent: return ["Noted. Reworking it."]
        case .questionAnswered: return ["Noted.", "That settles it."]
        case .waitingClosed: return ["Closed. One less thing to chase."]
        case .correctionAccepted: return ["Corrected.", "Noted. Fixed."]
        }
    }

    public static func line(for moment: KitMoment, count: Int) -> String {
        let lines = lines(for: moment)
        return lines[((count % lines.count) + lines.count) % lines.count]
    }
}

/// Counts each moment since the app started and hands out the next line.
@MainActor
public final class KitVoiceCounter {
    private var counts: [KitMoment: Int] = [:]

    public init() {}

    public func next(_ moment: KitMoment) -> String {
        let n = counts[moment, default: 0]
        counts[moment] = n + 1
        return KitVoice.line(for: moment, count: n)
    }
}

/// A line Kit shows after a confirmed command, until its deadline.
struct KitConfirmation: Equatable, Sendable {
    var handle: String
    var moment: KitMoment
    var line: String
    var deadline: Date
}
