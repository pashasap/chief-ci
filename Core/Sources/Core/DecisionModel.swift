import Foundation
import Observation

public enum DecisionState: Equatable, Sendable { case pending, confirmed, failed }

public enum DecisionAction: Equatable, Sendable { case approve, reject }

@MainActor @Observable
public final class DecisionModel {
    public private(set) var actionSerial = 0
    private var receipt: (handle: String, type: String, message: String, until: Date, previous: When?)?
    var reopenedHandles: Set<String> = []
    private var previousWhens: [String: When] = [:]

    public var actionBar: ActionBar? {
        guard let receipt, clock.now < receipt.until else { return nil }
        let inverseExists = receipt.type == "task.done" || (receipt.type == "task.defer" && receipt.previous != nil)
        let taskExists = inbox.snapshot?.tasks.contains { $0.handle == receipt.handle && !($0.rev ?? "").isEmpty } == true
        let undo = inverseExists && taskExists ? InboxControl(label: "Undo", role: .normal,
            isEnabled: canDecide, disabledReason: cannotDecideReason, state: .idle, action: .undo) : nil
        return ActionBar(message: receipt.message, undo: undo)
    }

    public func shouldCloseSheet(handle: String) -> Bool {
        guard let receipt else { return false }
        return receipt.handle == handle
    }

    public func undoLastAction() async {
        guard actionBar?.undo?.isEnabled == true, let receipt,
            let task = inbox.snapshot?.tasks.first(where: { $0.handle == receipt.handle }) else { return }
        resetState(task.handle)
        if receipt.type == "task.done" {
            await send("task.reopen", handle: task.handle, rev: task.rev, args: [:])
        } else if receipt.type == "task.defer", let when = receipt.previous {
            let value: JSONValue = .object(["kind": .string(when.kind), "date": when.date.map(JSONValue.string) ?? .null])
            await send("task.defer", handle: task.handle, rev: task.rev, args: ["when": value])
        }
        self.receipt = nil
    }
    public static let undoWindow: TimeInterval = 5
    public static let offlineReason = "No connection. Decisions need one."

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

    public func retry() async {
        guard let command = failedCommand, canDecide else { return }
        failedCommand = nil
        await deliver(command)
    }

    // MARK: Sending

    /// The one way a command is built: only from an item that is in the current snapshot and carries a rev.
    /// Without one nothing is built or sent; the screens disable the control with `missingItemReason`.
    func send(_ type: String, handle: String, rev: String?, args: [String: JSONValue]) async {
        guard let rev, !rev.isEmpty else { return }
        guard canDecide, states[handle] == nil else { return }
        message = nil
        confirmation = nil
        await deliver(CommandBuilder.make(type: type, handle: handle, rev: rev, args: args))
    }

    private func deliver(_ command: Command) async {
        if command.type == "task.defer", previousWhens[command.id] == nil,
            let when = inbox.snapshot?.tasks.first(where: { $0.handle == command.handle })?.when {
            previousWhens[command.id] = when
        }
        states[command.handle] = .pending
        guard let request = makeRequest(command) else { return notPaired(command) }
        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch {
            return fail(command)
        }
        switch response.status {
        case 200 where isOK(response.body): await confirmAfterRefetch(command)
        case 401: notPaired(command)
        case 409: await reloadAfterConflict(command)
        case 400, 404, 422: refuse(command, body: response.body)
        default: fail(command)
        }
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
        await inbox.refresh()
        message = "This changed while you were looking. Reloaded."
    }

    private func confirmAfterRefetch(_ command: Command) async {
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
            receipt = (command.handle, command.type, text, clock.now.addingTimeInterval(Self.undoWindow), previousWhens[command.id])
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
