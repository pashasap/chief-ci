import Foundation
import Observation

/// App-level state: the selected tab and the requests that links make of the views.
@MainActor
@Observable
public final class AppCoordinator {
    public var selectedTab: AppTab = .inbox
    public private(set) var recordRequested = false
    public private(set) var pendingPairLink: String?

    @ObservationIgnored private let router: AppRouter

    public init(router: AppRouter = AppRouter()) {
        self.router = router
    }

    /// Nothing happens without a link, so a plain launch never starts a recording.
    public func launch(url: URL?) {
        apply(router.launch(url: url))
    }

    public func open(url: URL) {
        apply(router.handle(url: url))
    }

    public func open(notificationIdentifier: String) {
        apply(router.handle(notificationIdentifier: notificationIdentifier))
    }

    public func consumeRecordRequest() -> Bool {
        defer { recordRequested = false }
        return recordRequested
    }

    public func consumePairLink() -> String? {
        defer { pendingPairLink = nil }
        return pendingPairLink
    }

    private func apply(_ action: AppAction?) {
        switch action {
        case .startRecording:
            recordRequested = true
        case .pair(let link):
            selectedTab = .settings
            pendingPairLink = link
        case .openTab(let tab):
            selectedTab = tab
        case nil:
            break
        }
    }
}
