import Foundation
import Observation

public enum DecisionState: Equatable, Sendable { case pending, confirmed, failed }

public enum DecisionAction: Equatable, Sendable { case approve, reject }

@MainActor @Observable
public final class DecisionModel {
    public private(set) var actionSerial = 0
    private typealias Receipt = (handle: String, type: String, message: String, until: Date, previous: When?)
    private var receipt: Receipt?
    var reopenedHandles: Set<String> = []
    private var previousWhens: [String: When] = [:]

    private var activeReceipt: Receipt? {
        guard let receipt, clock.now < receipt.until else { return nil }
        return receipt
    }

    public var actionBar: ActionBar? {
        guard let receipt = activeReceipt else { return nil }
        return ActionBar(message: receipt.message, undo: undoControl(for: receipt))
    }

    var todayBar: TodayBar? {
        guard let receipt = activeReceipt, receipt.type == "task.done",
            var undo = undoControl(for: receipt) else { return nil }
        undo.action = .reopen(receipt.handle)
        return TodayBar(message: receipt.message, undo: undo)
    }

    private func undoRev(for receipt: Receipt) -> String? {
        guard receipt.type == "task.done" || (receipt.type == "task.defer" && receipt.previous != nil),
            let rev = inbox.snapshot?.tasks.first(where: { $0.handle == receipt.handle })?.rev,
            !rev.isEmpty else { return nil }
        return rev
    }

    private func undoControl(for receipt: Receipt) -> InboxControl? {
        guard undoRev(for: receipt) != nil else { return nil }
        let state = state(for: receipt.handle)
        return InboxControl(label: "Undo", role: .normal, isEnabled: canDecide && (state == nil || state == .confirmed),
            disabledReason: cannotDecideReason, state: .idle, action: .undo)
    }

    public func shouldCloseSheet(handle: String) -> Bool {
        guard let receipt else { return false }
        return receipt.handle == handle
    }

    func undoTaskDone(_ handle: String) async {
        guard let receipt = activeReceipt, receipt.type == "task.done", receipt.handle == handle else { return }
        await undo(receipt)
    }

    public func undoLastAction() async {
        guard let receipt = activeReceipt else { return }
        await undo(receipt)
    }

    private func undo(_ receipt: Receipt) async {
        guard undoControl(for: receipt)?.isEnabled == true, let rev = undoRev(for: receipt) else { return }
        let command: Command
        if let when = receipt.previous, receipt.type == "task.defer" {
            let value: JSONValue = .object(["kind": .string(when.kind), "date": when.date.map(JSONValue.string) ?? .null])
            command = CommandBuilder.make(type: "task.defer", handle: receipt.handle, rev: rev, args: ["when": value])
        } else {
            command = CommandBuilder.make(type: "task.reopen", handle: receipt.handle, rev: rev, args: [:])
        }
        resetState(receipt.handle)
        // Consume the shared receipt before awaiting the inverse so neither surface can offer it again.
        self.receipt = nil
        await send(command, recordsReceipt: false)
    }
    public static let undoWindow: TimeInterval = 5
    public static let offlineReason = "No connection. Decisions need one."
    /// Commands whose every failure keeps a Retry and shows the server's message, except 401 and 409.
    static let retryableFailureTypes: Set<String> = [
        "proposal.drop", "candidate.research", "candidate.drop", "task.defer",
    ]

    public private(set) var message: String?

    /// Task sheet state shared by every sheet instance: tasks awaiting a drop confirmation, and the Dropped bar.
    var dropConfirming: Set<String> = []
    var dropBar: DoneBarState?

    private var states: [String: DecisionState] = [:]
    /// Kit's line for the last confirmed command, while it is on screen.
    private(set) var confirmation: KitConfirmation?
    @ObservationIgnored private let voice = KitVoiceCounter()
    private var failedCommand: Command?
    private var undoDeadline: Date?

    private let inbox: InboxModel
    private let transport: any HTTPTransport
    private let pairing: Pairing
    private let clock: any Clock

    public init(inbox: InboxModel, transport: any HTTPTransport, pairing: Pairing, clock: any Clock) {
        self.inbox = inbox
        self.transport = transport
        self.pairing = pairing
        self.clock = clock
    }

    // MARK: Queries

    public var canDecide: Bool { !inbox.isOffline }

    public var cannotDecideReason: String? { canDecide ? nil : Self.offlineReason }

    public var undoAvailable: Bool {
        guard let deadline = undoDeadline else { return false }
        return clock.now < deadline
    }

    public func state(for handle: String) -> DecisionState? { states[handle] }

    public static let conflictText = "This changed while you were looking. Reloaded."

    /// Handles whose last command met a stale revision; cleared by the next command for the handle.
    private var conflicts: Set<String> = []

    /// The one plain status every surface shows for `handle`: Sending, Did not go through or the conflict line.
    public func statusText(for handle: String) -> String? {
        switch states[handle] {
        case .pending: return "Sending"
        case .failed: return "Did not go through"
        default: return conflicts.contains(handle) ? Self.conflictText : nil
        }
    }

    /// Kit's line after the server confirmed a command, for `KitVoice.barSeconds`; nil while pending or failed.
    public var kitLine: String? { activeConfirmation?.line }

    var activeConfirmation: KitConfirmation? {
        guard let confirmation, clock.now < confirmation.deadline else { return nil }
        return confirmation
    }

    var now: Date { clock.now }

    var failedCommandType: String? { failedCommand?.type }

    /// Forgets a settled state so the same item can take another command.
    func resetState(_ handle: String) {
        if states[handle] == .confirmed { states[handle] = nil }
    }

    public func retryAvailable(for handle: String) -> Bool {
        failedCommand?.handle == handle && states[handle] == .failed
    }

    public func isEnabled(_ action: DecisionAction, for handle: String) -> Bool {
        canDecide && states[handle] == nil
    }

    // MARK: Decisions

    public func approve(_ proposal: Proposal) async {
        await send("proposal.approve", handle: proposal.handle, rev: proposal.rev, args: [:])
    }

    public func reject(_ proposal: Proposal) async {
        await send("proposal.reject", handle: proposal.handle, rev: proposal.rev, args: [:])
    }

    public func drop(_ proposal: Proposal) async {
        await send("proposal.drop", handle: proposal.handle, rev: proposal.rev, args: [:])
    }

    public func change(_ proposal: Proposal, text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await send("proposal.change", handle: proposal.handle, rev: proposal.rev, args: ["text": .string(text)])
    }

    public func answer(_ question: Question, optionIndex: Int) async {
        await send("question.answer", handle: question.handle, rev: question.rev, args: ["option": .int(optionIndex)])
    }

    public func answer(_ question: Question, text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await send("question.answer", handle: question.handle, rev: question.rev, args: ["text": .string(text)])
    }

    /// Asks for research on a candidate project. The queued action handle arrives only in a later snapshot.
    public func research(_ candidate: Candidate) async {
        await send("candidate.research", handle: candidate.handle, rev: candidate.rev, args: [:])
    }

    /// Deletes a candidate project. It is not a learning signal and carries no queued action.
    public func drop(_ candidate: Candidate) async {
        await send("candidate.drop", handle: candidate.handle, rev: candidate.rev, args: [:])
    }

    public func retry() async {
        guard let command = failedCommand, canDecide else { return }
        failedCommand = nil
        await deliver(command)
    }

    // MARK: Sending

    /// The one way a command is built: only from an item that is in the current snapshot and carries a rev.
    /// Without one nothing is built or sent; the screens disable the control with `missingItemReason`.
    func send(_ type: String, handle: String, rev: String?, args: [String: JSONValue]) async {
        guard let rev, !rev.isEmpty, canDecide, states[handle] == nil else { return }
        await send(CommandBuilder.make(type: type, handle: handle, rev: rev, args: args))
    }

    private func send(_ command: Command, recordsReceipt: Bool = true) async {
        if command.type == "task.reopen", receipt?.type == "task.done", receipt?.handle == command.handle {
            receipt = nil
        }
        message = nil
        confirmation = nil
        await deliver(command, recordsReceipt: recordsReceipt)
    }

    private func deliver(_ command: Command, recordsReceipt: Bool = true) async {
        if command.type == "task.defer", previousWhens[command.id] == nil,
            let when = inbox.snapshot?.tasks.first(where: { $0.handle == command.handle })?.when {
            previousWhens[command.id] = when
        }
        states[command.handle] = .pending
        conflicts.remove(command.handle)
        guard let request = makeRequest(command) else { return notPaired(command) }
        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch {
            return fail(command)
        }
        switch response.status {
        case 200 where isOK(response.body): await confirmAfterRefetch(command, recordsReceipt: recordsReceipt)
        case 401: notPaired(command)
        case 409: await reloadAfterConflict(command)
        case _ where command.type == "proposal.drop" || isIdeaCommand(command):
            fail(command)
            message = (try? JSONDecoder().decode(ErrorBody.self, from: response.body))?.error.message
                ?? "Did not go through"
        case 400, 404, 422: refuse(command, body: response.body)
        default: fail(command)
        }
    }

    /// An Ideas command, a move to a task or an idea, or a correction of a candidate project, keeps its
    /// Retry and the server's message.
    private func isIdeaCommand(_ command: Command) -> Bool {
        if Self.retryableFailureTypes.contains(command.type) { return true }
        if command.type == "item.reclassify" {
            guard case .string(let destination)? = command.args["to"] else { return false }
            return destination == "task" || destination == "idea"
        }
        guard command.type == "item.correct" else { return false }
        return inbox.snapshot?.candidates.contains { $0.handle == command.handle } == true
    }

    /// The server refused the command: show its message as sent, offer no Retry.
    private func refuse(_ command: Command, body: Data) {
        states[command.handle] = nil
        let sent = (try? JSONDecoder().decode(ErrorBody.self, from: body))?.error.message
        message = sent ?? "Did not go through"
    }

    private func makeRequest(_ command: Command) -> HTTPRequest? {
        guard let base = pairing.baseURL, let token = pairing.token,
            let url = URL(string: base.hasSuffix("/") ? base + "v1/commands" : base + "/v1/commands"),
            let body = try? JSONEncoder().encode(command)
        else { return nil }
        let headers = ["Authorization": "Bearer " + token, "Content-Type": "application/json"]
        return HTTPRequest(method: "POST", url: url, headers: headers, body: body)
    }

    private func isOK(_ body: Data) -> Bool {
        guard let value = try? JSONDecoder().decode([String: JSONValue].self, from: body) else { return false }
        return value["ok"] == .bool(true)
    }

    private func fail(_ command: Command) {
        states[command.handle] = .failed
        failedCommand = command
    }

    private func notPaired(_ command: Command) {
        message = "The app is not paired"
        fail(command)
    }

    private func reloadAfterConflict(_ command: Command) async {
        states[command.handle] = nil
        conflicts.insert(command.handle)
        await inbox.refresh()
        message = Self.conflictText
    }

    private func confirmAfterRefetch(_ command: Command, recordsReceipt: Bool) async {
        await inbox.refresh()
        guard isSettled(command) else { return fail(command) }
        states[command.handle] = .confirmed
        if command.type == "task.reopen" { reopenedHandles.insert(command.handle) }
        if command.type == "task.done" { reopenedHandles.remove(command.handle) }
        if let moment = KitMoment.confirming(command.type) {
            let deadline = clock.now.addingTimeInterval(KitVoice.barSeconds)
            confirmation = KitConfirmation(
                handle: command.handle, moment: moment, line: voice.next(moment), deadline: deadline)
        }
        if command.type.hasPrefix("task.") || command.type.hasPrefix("item.") {
            let text: String
            switch command.type {
            case "task.defer": text = "Moved."
            case "task.drop": text = TaskSheetScreen.droppedMessage
            case "task.reopen": text = "Reopened."
            default: text = confirmation?.line ?? "Corrected."
            }
            actionSerial += 1
            if recordsReceipt {
                receipt = (command.handle, command.type, text, clock.now.addingTimeInterval(Self.undoWindow), previousWhens[command.id])
            }
        }
        if command.type == "proposal.approve" || command.type == "proposal.reject" {
            undoDeadline = clock.now.addingTimeInterval(Self.undoWindow)
        }
    }

    private func isSettled(_ command: Command) -> Bool {
        guard let snapshot = inbox.snapshot else { return false }
        if command.type.hasPrefix("item.") { return true }
        let state: String?
        if command.type.hasPrefix("proposal.") {
            state = snapshot.proposals.first { $0.handle == command.handle }?.state
        } else {
            state = snapshot.questions.first { $0.handle == command.handle }?.state
        }
        guard let state else { return true }
        return state != "open"
    }
}
