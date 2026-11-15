import Foundation
import Observation

@MainActor @Observable
public final class InboxModel {
    public private(set) var needsYou: [NeedsYouRow] = []
    public private(set) var recent: [RecentRow] = []
    public private(set) var lastUpdatedText = ""
    public private(set) var isOffline = false
    public private(set) var showsEmptyState = false
    public private(set) var emptyStateText: String? = InboxModel.loadingText
    public private(set) var notice: String?
    public private(set) var offersPairing = false
    public private(set) var needsPolling = false
    public private(set) var snapshot: Snapshot?
    /// How many snapshot elements the last fetch could not decode.
    public private(set) var skippedCount = 0

    /// True once a refresh has finished, whatever its outcome.
    public private(set) var hasLoaded = false
    /// Set by the app: the upload engine whose state the capture rows explain.
    public var uploader: UploadEngine?
    /// Called after every refresh that left a snapshot on screen (names list, reminders).
    @ObservationIgnored public var afterRefresh: (@MainActor (Snapshot) async -> Void)?

    public var drafts = InboxDrafts()
    public var coordinator: AppCoordinator?
    @ObservationIgnored public weak var loop: AppLoop?

    public static let loadingText = "Loading"

    private let repository: SnapshotRepository
    private let store: OutboxStore
    private let clock: any Clock

    public init(repository: SnapshotRepository, store: OutboxStore, clock: any Clock) {
        self.repository = repository
        self.store = store
        self.clock = clock
        showCached()
    }

    public var needsYouCount: Int {
        guard let snapshot else { return 0 }
        return snapshot.proposals.filter { $0.state == "open" }.count
            + snapshot.questions.filter { $0.state == "open" }.count + snapshot.unreadable.count
    }

    public func sourceCapture(for handle: String) -> Capture? {
        guard let snapshot else { return nil }
        let id = snapshot.tasks.first { $0.handle == handle }?.capture
            ?? snapshot.notes.first { $0.handle == handle }?.capture
            ?? snapshot.proposals.first { $0.handle == handle }?.capture
            ?? snapshot.questions.first { $0.handle == handle }?.capture
            ?? snapshot.results.first { $0.handle == handle }?.capture
        return snapshot.captures.first { $0.id == id }
            ?? snapshot.captures.first { $0.items.contains { $0.handle == handle } }
    }

    public func onForeground() async { await refresh() }

    public func pullToRefresh() async { await refresh() }

    /// Shows the cached snapshot and the outbox at once, before the network answers. Changes no notice.
    public func showCached() {
        let cached = repository.cached()
        if let cached {
            snapshot = cached.snapshot
            skippedCount = cached.skipped.count
            needsYou = InboxRows.needsYou(cached.snapshot)
            needsPolling = PollingPolicy.needsPolling(cached.snapshot)
            showsEmptyState = false
            emptyStateText = nil
            lastUpdatedText = "Showing saved data from " + age(cached) + (isOffline ? ", no connection" : "")
        }
        recent = InboxRows.recent(snapshot: cached?.snapshot, outbox: store.records())
        if cached == nil {
            snapshot = nil
            needsYou = []
            needsPolling = false
            skippedCount = 0
            lastUpdatedText = ""
            showsEmptyState = true
            offersPairing = !repository.isPaired
            notice = offersPairing ? "Not paired" : nil
            emptyStateText = offersPairing ? "Not paired" : Self.loadingText
        }
    }

    private func age(_ cached: CachedSnapshot) -> String {
        AgeText.when(cached.fetchedAt, now: clock.now, zone: InboxRows.timeZone(cached.snapshot.timezone))
    }

    public func refresh() async {
        let outcome = await repository.refresh()
        hasLoaded = true
        let cached = repository.cached()
        snapshot = cached?.snapshot
        skippedCount = cached?.skipped.count ?? 0
        needsYou = cached.map { InboxRows.needsYou($0.snapshot) } ?? []
        recent = InboxRows.recent(snapshot: cached?.snapshot, outbox: store.records())
        needsPolling = cached.map { PollingPolicy.needsPolling($0.snapshot) } ?? false
        isOffline = outcome == .failed
        offersPairing = outcome == .unauthorized
        showsEmptyState = cached == nil
        emptyStateText = cached == nil ? (outcome == .unauthorized ? "Not paired" : makeNotice(outcome: outcome, hasCache: false)) : nil
        notice = makeNotice(outcome: outcome, hasCache: cached != nil)
        lastUpdatedText = makeUpdatedText(cached, outcome: outcome)
        if let shown = cached?.snapshot, let afterRefresh { await afterRefresh(shown) }
    }

    private func makeNotice(outcome: RefreshOutcome, hasCache: Bool) -> String? {
        if outcome == .unauthorized { return "Not paired" }
        if let cacheNotice = repository.cacheNotice { return cacheNotice }
        if outcome == .failed { return hasCache ? nil : "No connection, and nothing is saved yet" }
        return SnapshotRepository.failureText(outcome)
    }

    private func makeUpdatedText(_ cached: CachedSnapshot?, outcome: RefreshOutcome) -> String {
        guard let cached else { return "" }
        let time = age(cached)
        switch outcome {
        case .updated, .notModified: return "Updated \(time)"
        case .failed: return "Showing saved data from \(time), no connection"
        case .unauthorized, .unreadable, .serverError, .notSaved: return "Showing saved data from \(time)"
        }
    }
}
