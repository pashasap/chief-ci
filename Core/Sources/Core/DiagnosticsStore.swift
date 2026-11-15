import Foundation

/// Puts plain text on the system clipboard; the real one lives in the app target.
public protocol ClipboardAdapter: Sendable {
    func copy(_ text: String)
}

public struct DiagnosticsState: Codable, Equatable, Sendable {
    public var answerAt: Date?
    public var answerStatus: Int?
    public var problemText: String?
    public var problemAt: Date?

    public init() {}
}

/// Last answer and last problem of the server, kept in a small file so Settings can show them later.
public final class DiagnosticsStore: @unchecked Sendable {
    public static let fileName = "diagnostics.state"

    private let files: any FileStore
    private let clock: any Clock
    private let lock = NSLock()
    /// Set when the diagnostics file could not be written or read.
    public private(set) var storageProblem: String?

    public init(files: any FileStore, clock: any Clock) {
        self.files = files
        self.clock = clock
    }

    public func load() -> DiagnosticsState {
        lock.lock()
        defer { lock.unlock() }
        return read()
    }

    public func recordAnswer(status: Int) {
        update { state, now in
            state.answerAt = now
            state.answerStatus = status
        }
    }

    public func recordProblem(_ text: String) {
        update { state, now in
            state.problemText = text
            state.problemAt = now
        }
    }

    private func update(_ change: (inout DiagnosticsState, Date) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        var state = read()
        change(&state, clock.now)
        do {
            try files.write(JSONEncoder().encode(state), name: Self.fileName)
        } catch {
            storageProblem = "Diagnostics could not be saved"
        }
    }

    private func read() -> DiagnosticsState {
        do {
            guard let data = try files.read(Self.fileName) else { return DiagnosticsState() }
            return try JSONDecoder().decode(DiagnosticsState.self, from: data)
        } catch {
            storageProblem = "Diagnostics could not be read"
            return DiagnosticsState()
        }
    }
}
