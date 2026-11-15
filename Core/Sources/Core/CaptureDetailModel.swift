import Foundation
import Observation

public struct CaptureItemRow: Equatable, Sendable {
    public var handle: String
    public var text: String
    public var kind: String
    public var label: String?
    public var queuedLine: String? = nil
}

/// The capture sheet: what the user said, and the items Kit filed from it.
@MainActor @Observable
public final class CaptureDetailModel {
    public let captureId: String
    public let youSaidHeading = "You said"
    public let filedHeading = "Filed from this"
    public let youSaidText: String
    public let status: String
    public let items: [CaptureItemRow]
    /// True while the capture is still waiting in the outbox and nothing has been filed from it.
    public let isOnThisPhone: Bool

    private let snapshot: Snapshot?
    private let decisions: DecisionModel?

    public init(capture: Capture, snapshot: Snapshot, decisions: DecisionModel) {
        captureId = capture.id
        youSaidText = capture.text
        status = InboxRows.statusLabel(capture.status)
        items = capture.items.map { item in
            var row = CaptureItemRow(
                handle: item.handle, text: item.text, kind: item.kind, label: Self.label(for: item.kind))
            if item.kind == "proposal" {
                row.queuedLine = snapshot.proposals.first { $0.handle == item.handle }?.queuedLine
            }
            return row
        }
        isOnThisPhone = false
        self.snapshot = snapshot
        self.decisions = decisions
    }

    public init(record: OutboxRecord) {
        captureId = record.clientId
        youSaidText = record.text
        status = "On this iPhone"
        items = []
        isOnThisPhone = true
        snapshot = nil
        decisions = nil
    }

    static func label(for kind: String) -> String? {
        switch kind {
        case "proposal": return "Kit suggests"
        case "question": return "Kit asks"
        default: return nil
        }
    }

    public func approve(handle: String) async {
        guard let proposal = proposal(handle) else { return }
        await decisions?.approve(proposal)
    }

    public func reject(handle: String) async {
        guard let proposal = proposal(handle) else { return }
        await decisions?.reject(proposal)
    }

    public func change(handle: String, text: String) async {
        guard let proposal = proposal(handle) else { return }
        await decisions?.change(proposal, text: text)
    }

    public func answer(handle: String, optionIndex: Int) async {
        guard let question = question(handle) else { return }
        await decisions?.answer(question, optionIndex: optionIndex)
    }

    public func answer(handle: String, text: String) async {
        guard let question = question(handle) else { return }
        await decisions?.answer(question, text: text)
    }

    private func proposal(_ handle: String) -> Proposal? {
        snapshot?.proposals.first { $0.handle == handle }
    }

    private func question(_ handle: String) -> Question? {
        snapshot?.questions.first { $0.handle == handle }
    }
}
