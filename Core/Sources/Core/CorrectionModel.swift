import Foundation
import Observation

/// Corrections of filed items (task or note), sent through the shared DecisionModel pipeline.
@MainActor @Observable
public final class CorrectionModel {
    public var removeConfirming: Set<String> = []
    private let decisions: DecisionModel
    private let inbox: InboxModel

    public init(decisions: DecisionModel, inbox: InboxModel, transport: any HTTPTransport, pairing: Pairing) {
        self.decisions = decisions
        self.inbox = inbox
    }

    public var canCorrect: Bool { decisions.canDecide }

    public var cannotCorrectReason: String? { decisions.cannotDecideReason }

    public func state(for handle: String) -> DecisionState? { decisions.state(for: handle) }

    public func retryAvailable(for handle: String) -> Bool { decisions.retryAvailable(for: handle) }

    public func isEnabled(handle: String) -> Bool { decisions.isEnabled(.approve, for: handle) }

    public func justAnIdea(handle: String) async {
        await send("item.reclassify", handle: handle, args: ["to": .string("idea")])
    }

    public func itsATask(handle: String) async {
        let when: JSONValue = .object(["kind": .string("later"), "date": .null])
        await send("item.reclassify", handle: handle, args: ["to": .string("task"), "when": when])
    }

    public func notThis(handle: String) async {
        await send("item.remove", handle: handle, args: [:])
    }

    public func correct(handle: String, text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        await send("item.correct", handle: handle, args: ["text": .string(text)])
    }

    public func retry() async { await decisions.retry() }

    private func send(_ type: String, handle: String, args: [String: JSONValue]) async {
        await decisions.send(type, handle: handle, rev: rev(of: handle), args: args)
    }

    private func rev(of handle: String) -> String? {
        guard let snapshot = inbox.snapshot else { return nil }
        if let task = snapshot.tasks.first(where: { $0.handle == handle }) { return task.rev }
        if let note = snapshot.notes.first(where: { $0.handle == handle }) { return note.rev }
        return snapshot.candidates.first { $0.handle == handle }?.rev
    }
}
