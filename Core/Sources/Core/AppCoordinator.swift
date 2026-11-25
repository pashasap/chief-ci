import Foundation
import Observation

/// App-level state: the selected tab, active route and the requests that links make of the views.
@MainActor
@Observable
public final class AppCoordinator {
    public var selectedTab: AppTab = .inbox {
        didSet {
            if !suppressRouteSync {
                activeRoute = .tab(selectedTab)
            }
        }
    }
    public var activeRoute: AppRoute = .tab(.inbox)
    public private(set) var recordRequested = false
    public private(set) var pendingPairLink: String?

    @ObservationIgnored private let router: AppRouter
    @ObservationIgnored private var suppressRouteSync = false

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

    public func open(route: AppRoute) {
        switch route {
        case .tab(let tab):
            selectedTab = tab
        case .brief, .search:
            suppressRouteSync = true
            selectedTab = .home
            suppressRouteSync = false
            activeRoute = route
        }
    }

    public func openWrite(recording: RecordingModel, typed: TypedCaptureModel) async {
        typed.reopen()
        recording.openWrite()
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
        case .openRoute(let route):
            open(route: route)
        case nil:
            break
        }
    }
}
