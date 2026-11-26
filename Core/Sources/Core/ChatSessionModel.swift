import Foundation
import Observation

/// One message in a Quick Chat session. Nothing here is persisted.
public struct ChatTurn: Equatable, Sendable {
    public enum Role: String, Equatable, Sendable {
        case user
        case assistant
    }

    public var role: Role
    public var content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

/// The state of one opened chat. The session lives in memory only and is
/// dropped when the chat closes; no file store is involved.
@MainActor
@Observable
public final class ChatSessionModel {
    public static let maximumMessages = 40
    public static let maximumMessageCharacters = 16_000
    public static let maximumTotalCharacters = 64_000

    public private(set) var sessionID = ""
    public private(set) var turns: [ChatTurn] = []
    public private(set) var notice: String?
    public private(set) var isSending = false
    public var draft = ""

    private let transport: any HTTPTransport
    private let pairing: Pairing
    private let makeSessionID: @Sendable () -> UUID

    public static let unavailableNotice = "Chat is unavailable. Check the connection and try again."
    public static let messageCountNotice = "This chat is full. Close it and start a new one."
    public static let messageLengthNotice = "That message is too long to send."
    public static let totalLengthNotice = "This chat is long enough. Close it and start a new one."
    public static let busyNotice = "One message at a time."

    public init(
        transport: any HTTPTransport,
        pairing: Pairing,
        makeSessionID: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.transport = transport
        self.pairing = pairing
        self.makeSessionID = makeSessionID
    }

    /// Opens the chat with a new lowercase session id and no turns.
    public func open() {
        sessionID = makeSessionID().uuidString.lowercased()
        turns = []
        draft = ""
        notice = nil
    }

    /// Closes the chat and forgets the session and its turns.
    public func close() {
        sessionID = ""
        turns = []
        draft = ""
        notice = nil
    }

    public func send(text: String) async {
        guard !isSending else {
            notice = Self.busyNotice
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let refusal = limitNotice(for: trimmed) else {
            draft = trimmed
            isSending = true
            defer { isSending = false }
            notice = nil
            await deliver(trimmed)
            return
        }
        draft = trimmed
        notice = refusal
    }

    private func limitNotice(for trimmed: String) -> String? {
        if trimmed.count > Self.maximumMessageCharacters { return Self.messageLengthNotice }
        if turns.count + 1 > Self.maximumMessages { return Self.messageCountNotice }
        let earlier = turns.reduce(0) { $0 + $1.content.count }
        if earlier + trimmed.count > Self.maximumTotalCharacters { return Self.totalLengthNotice }
        return nil
    }

    private func deliver(_ trimmed: String) async {
        guard let request = makeRequest(for: trimmed) else {
            notice = Self.unavailableNotice
            return
        }
        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch {
            notice = Self.unavailableNotice
            return
        }
        guard response.status == 200, let reply = replyText(response.body) else {
            notice = Self.unavailableNotice
            return
        }
        turns.append(ChatTurn(role: .user, content: trimmed))
        turns.append(ChatTurn(role: .assistant, content: reply))
        draft = ""
        notice = nil
    }

    private func makeRequest(for trimmed: String) -> HTTPRequest? {
        guard let base = pairing.baseURL, let token = pairing.token else { return nil }
        guard let url = URL(string: base + "/v1/chat") else { return nil }
        var messages = turns.map { WireMessage(role: $0.role.rawValue, content: $0.content) }
        messages.append(WireMessage(role: ChatTurn.Role.user.rawValue, content: trimmed))
        let payload = WireBody(session_id: sessionID, messages: messages)
        guard let body = try? JSONEncoder().encode(payload) else { return nil }
        return HTTPRequest(
            method: "POST",
            url: url,
            headers: ["Authorization": "Bearer " + token, "Content-Type": "application/json"],
            body: body)
    }

    private func replyText(_ body: Data) -> String? {
        guard let decoded = try? JSONDecoder().decode(WireReply.self, from: body) else { return nil }
        return decoded.reply.isEmpty ? nil : decoded.reply
    }

    private struct WireMessage: Encodable {
        let role: String
        let content: String
    }

    private struct WireBody: Encodable {
        let session_id: String
        let messages: [WireMessage]
    }

    private struct WireReply: Decodable {
        let reply: String
    }
}
