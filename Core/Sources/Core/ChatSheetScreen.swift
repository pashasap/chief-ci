import Foundation

/// Everything the Quick Chat sheet shows and how it measures, as plain values.
/// The view renders this and holds no strings or layout numbers of its own.
public struct ChatSheetScreen: Equatable, Sendable {
    /// The spoken and visible words of the sheet.
    public struct Labels: Equatable, Sendable {
        public let title: String
        public let close: String
        public let closeAccessibility: String
        public let fieldPrompt: String
        public let fieldAccessibility: String
        public let send: String
        public let sending: String
        public let sendAccessibility: String
        public let youSaidPrefix: String
        public let replyPrefix: String
    }

    /// The spacing the sheet is laid out with.
    public struct Metrics: Equatable, Sendable {
        public let sheetSpacing: Double
        public let verticalPadding: Double
        public let horizontalPadding: Double
        public let turnSpacing: Double
        public let bubblePadding: Double
        public let composerSpacing: Double
    }

    public let labels: Labels
    public let metrics: Metrics

    /// The one question the chat-exchange audit stop sends from its fixed fake transport.
    public static let seedQuestion = "What is the capital of France?"
    /// The root accessibility identifier the chat sheet carries for its audit stop.
    public static let auditRootIdentifier = "kit.audit.chat"

    public init() {
        labels = Labels(
            title: "Quick Chat",
            close: "Close",
            closeAccessibility: "Close Quick Chat",
            fieldPrompt: "Ask Kit",
            fieldAccessibility: "Message",
            send: "Send",
            sending: "Sending",
            sendAccessibility: "Send message",
            youSaidPrefix: "You said ",
            replyPrefix: "Reply ")
        metrics = Metrics(
            sheetSpacing: 12,
            verticalPadding: 12,
            horizontalPadding: 16,
            turnSpacing: 10,
            bubblePadding: 12,
            composerSpacing: 10)
    }

    /// The spoken text of one turn: who said it, then what was said.
    public func spokenText(for turn: ChatTurn) -> String {
        let prefix = turn.role == .user ? labels.youSaidPrefix : labels.replyPrefix
        return prefix + turn.content
    }

    /// The Send control's own label while a request is in flight.
    public func sendTitle(isSending: Bool) -> String {
        isSending ? labels.sending : labels.send
    }
}
