import Foundation

public enum RefreshOutcome: Equatable, Sendable {
    case updated, notModified, unauthorized
    /// The request did not get an answer (network error).
    case failed
    /// The server answered, but the body was not a snapshot.
    case unreadable
    case serverError(Int)
    /// The answer was good but the cache file could not be written.
    case notSaved
}

public enum PollingPolicy {
    public static func interval(
        elapsedSinceStart: TimeInterval, needsPolling: Bool, inForeground: Bool
    ) -> TimeInterval? {
        guard needsPolling, inForeground else { return nil }
        return elapsedSinceStart < 120 ? 3 : 15
    }

    public static func needsPolling(_ snapshot: Snapshot) -> Bool {
        snapshot.captures.contains { $0.status == "on_server" || $0.status == "filing" }
            || snapshot.proposals.contains { $0.state == "changing" }
    }
}

public final class SnapshotRepository: @unchecked Sendable {
    private let transport: any HTTPTransport
    private let pairing: Pairing
    private let cache: SnapshotCache
    private let clock: any Clock
    /// When set, the repository records its answers and failure texts there.
    public var diagnostics: DiagnosticsStore?

    public init(
        transport: any HTTPTransport, pairing: Pairing, cache: SnapshotCache, clock: any Clock
    ) {
        self.transport = transport
        self.pairing = pairing
        self.cache = cache
        self.clock = clock
    }

    public func cached() -> CachedSnapshot? { cache.load() }

    public var isPaired: Bool { pairing.isPaired }

    public var cacheNotice: String? { cache.notice }

    /// The failure text of an outcome, or nil when it was not a failure.
    public static func failureText(_ outcome: RefreshOutcome) -> String? {
        switch outcome {
        case .updated, .notModified: return nil
        case .unauthorized: return "Not paired"
        case .failed: return "No connection"
        case .unreadable: return "Kit answered, but this build could not read it. See Settings, Diagnostics."
        case .serverError(let status): return "Kit's server has a problem (\(status)). Nothing is lost."
        case .notSaved: return "Kit answered, but this iPhone could not save it."
        }
    }

    public func refresh() async -> RefreshOutcome {
        let outcome = await fetch()
        if let text = Self.failureText(outcome) { diagnostics?.recordProblem(text) }
        return outcome
    }

    private func fetch() async -> RefreshOutcome {
        guard let base = pairing.baseURL, let token = pairing.token,
            let url = URL(string: base.hasSuffix("/") ? base + "v1/snapshot" : base + "/v1/snapshot")
        else { return .unauthorized }
        let current = cache.load()
        var headers = ["Authorization": "Bearer " + token]
        if let etag = current?.etag { headers["If-None-Match"] = etag }
        let response: HTTPResponse
        do {
            response = try await transport.send(HTTPRequest(method: "GET", url: url, headers: headers))
        } catch {
            return .failed
        }
        diagnostics?.recordAnswer(status: response.status)
        return handle(response, current: current)
    }

    private func handle(_ response: HTTPResponse, current: CachedSnapshot?) -> RefreshOutcome {
        switch response.status {
        case 200:
            let decoded: DecodedSnapshot
            do {
                decoded = try SnapshotDecoder.decode(response.body)
            } catch {
                return .unreadable
            }
            let etag = response.headers.first { $0.key.lowercased() == "etag" }?.value
            let fresh = CachedSnapshot(
                snapshot: decoded.snapshot, fetchedAt: clock.now, etag: etag, skipped: decoded.skipped)
            return save(fresh, success: .updated)
        case 304:
            guard var kept = current else { return .failed }
            kept.fetchedAt = clock.now
            return save(kept, success: .notModified)
        case 401:
            return .unauthorized
        case 500...599:
            return .serverError(response.status)
        default:
            return .unreadable
        }
    }

    private func save(_ cached: CachedSnapshot, success: RefreshOutcome) -> RefreshOutcome {
        do {
            try cache.save(cached)
            return success
        } catch {
            return .notSaved
        }
    }
}
