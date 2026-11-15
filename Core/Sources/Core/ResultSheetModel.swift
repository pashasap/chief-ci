import Foundation
import Observation

public enum DocPart: String, Sendable { case result, draft }

public enum DocState: Equatable, Sendable { case idle, loading, loaded, failed }

public struct DocSection: Equatable, Sendable {
    public var state: DocState = .idle
    public var blocks: [MarkdownBlock] = []
    public var error: String?
    public var retryLabel: String?
    public var markdown: String = ""
}

/// One result opened as a sheet: its recorded fields plus the full documents fetched with GET /v1/doc.
@MainActor @Observable
public final class ResultSheetModel {
    public let handle: String
    public private(set) var result = DocSection()
    public private(set) var draft = DocSection()
    public let askedLabel = "You asked"
    public let sheetTitle = "Result"
    public let doneLabel = "Done"

    private let inbox: InboxModel
    private let transport: any HTTPTransport
    private let pairing: Pairing

    public init(handle: String, inbox: InboxModel, transport: any HTTPTransport, pairing: Pairing) {
        self.handle = handle
        self.inbox = inbox
        self.transport = transport
        self.pairing = pairing
    }

    private var record: Result? { inbox.snapshot?.results.first { $0.handle == handle } }

    public var title: String { record?.title ?? handle }
    public var date: String { record?.date ?? "" }
    public var asked: String { record?.asked ?? "" }
    public var shortAnswer: String { record?.answer ?? "" }
    public var openDraftLabel: String? { record?.hasDraft == true ? "Open the draft" : nil }

    public func loadResult() async {
        result = DocSection(state: .loading)
        result = await fetch(.result)
    }

    public func retryResult() async { await loadResult() }

    public func openDraft() async {
        draft = DocSection(state: .loading)
        draft = await fetch(.draft)
    }

    public func retryDraft() async { await openDraft() }

    private func fetch(_ part: DocPart) async -> DocSection {
        guard let request = DocRequest.make(handle: handle, part: part, pairing: pairing),
            let response = try? await transport.send(request)
        else { return Self.failure("Could not load the full result", retry: true) }
        switch response.status {
        case 200:
            let markdown = DocBody.markdown(from: response.body)
            return DocSection(state: .loaded, blocks: MarkdownBlocks.parse(markdown), markdown: markdown)
        case 404: return Self.failure("Kit has no full text for this.", retry: false)
        case 401: return Self.failure("The app is not paired", retry: false)
        default: return Self.failure("Could not load the full result", retry: true)
        }
    }

    private static func failure(_ text: String, retry: Bool) -> DocSection {
        DocSection(state: .failed, blocks: [], error: text, retryLabel: retry ? "Retry" : nil)
    }
}

/// The body of GET /v1/doc: {handle, part, title, markdown}. Only the markdown is shown.
struct DocBody: Decodable {
    var handle: String?
    var part: String?
    var title: String?
    var markdown: String

    /// The markdown field of a JSON body; a body that is not that JSON is taken as plain markdown.
    static func markdown(from body: Data) -> String {
        if let decoded = try? JSONDecoder().decode(DocBody.self, from: body) { return decoded.markdown }
        return String(decoding: body, as: UTF8.self)
    }
}

/// Builds GET /v1/doc?handle=<handle>&part=<part> with the bearer token.
enum DocRequest {
    static func make(handle: String, part: DocPart, pairing: Pairing) -> HTTPRequest? {
        guard let base = pairing.baseURL, let token = pairing.token else { return nil }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+#")
        guard let encoded = handle.addingPercentEncoding(withAllowedCharacters: allowed),
            let url = URL(
                string: (base.hasSuffix("/") ? base : base + "/") + "v1/doc?handle=\(encoded)&part=\(part.rawValue)")
        else { return nil }
        return HTTPRequest(method: "GET", url: url, headers: ["Authorization": "Bearer " + token])
    }
}
