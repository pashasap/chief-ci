import AVFoundation
import SwiftUI
import Core

@main
struct ChiefApp: App {
    @State private var environment = AppEnvironment(audit: UserDefaults.standard.string(forKey: "auditStop")
        .flatMap { LayoutAuditFixture(id: $0) })
    @State private var auditReady = false

    var body: some Scene {
        WindowGroup {
            if environment.audit != nil {
                Group {
                    if auditReady { RootView(environment: environment) }
                    else { Color.clear }
                }
                .task {
                    guard !auditReady else { return }
                    await environment.prepareAudit()
                    auditReady = true
                }
            } else {
                RootView(environment: environment)
                    .onOpenURL { environment.coordinator.open(url: $0) }
            }
        }
    }
}

private struct RootSharedModels {
    let focusModel: FocusFilterModel
    let briefingAudio: BriefingAudioModel
    let framingStore: FramingSignalStore
    let onOpenChangeComposer: (String, String) -> Void
}

struct RootView: View {
    let environment: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var measuredBarHeight: CGFloat = 0
    @State private var focusModel: FocusFilterModel
    @State private var briefingAudio: BriefingAudioModel
    @State private var orbModel = CaptureOrbModel()
    @State private var framingStore: FramingSignalStore

    init(environment: AppEnvironment) {
        self.environment = environment
        if let audit = environment.audit {
            _focusModel = State(initialValue: FocusFilterModel(files: audit))
            _framingStore = State(initialValue: FramingSignalStore(files: audit, clock: environment.clock))
        } else {
            _focusModel = State(initialValue: FocusFilterModel(files: DirectoryFileStore(folderName: "chief")))
            _framingStore = State(initialValue: FramingSignalStore.shared)
        }
        _briefingAudio = State(initialValue: BriefingAudioModel(speech: BriefingAudioAdapter()))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                AmbientScreenCanvas()
                screenStack(proxy.size)
                OrbRadialMenuView(
                    model: orbModel,
                    availability: environment.recording.recordAvailability,
                    onVoiceSelected: present
                )
                .allowsHitTesting(orbModel.mode == .radialOpen)
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .task { wireCallbacksAndAuditRoute() }
        .task(id: scenePhase) { await handleScenePhase() }
        .task(id: environment.loop.wakeKey) { await runLoop() }
        .task { if environment.audit == nil { await monitorRecording() } }
        .task(id: environment.coordinator.recordRequested) {
            if environment.coordinator.consumeRecordRequest() { present() }
        }
        .onChange(of: orbModel.mode) { _, next in syncTypedContext(for: next) }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in
            guard environment.audit == nil else { return }
            Task { await environment.recording.handleInterruption() }
        }
        .onChange(of: environment.recording.isPanelPresented) { _, presented in
            if !presented {
                if orbModel.mode == .recording { orbModel.dismiss() }
                Task { await environment.sync() }
            }
        }
    }

    private func screenStack(_ size: CGSize) -> some View {
        let initial = RecordingPanelLayout(width: size.width, height: size.height,
            largestText: textSize.isAccessibilitySize)
        let layout = RecordingPanelLayout(width: size.width, height: size.height,
            largestText: initial.largestText, measuredBarHeight: measuredBarHeight)
        return VStack(spacing: 0) {
            content(layout)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom, spacing: 0) { orbComposerInset }
            if environment.recording.isPanelPresented { recordingPanel(layout) }
            bottomBar(initial)
                .frame(minHeight: initial.bottomBarHeight)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredBarHeight = $0 }
                .layoutPriority(1)
        }
    }

    private func content(_ layout: RecordingPanelLayout) -> some View {
        let shared = RootSharedModels(
            focusModel: focusModel,
            briefingAudio: briefingAudio,
            framingStore: framingStore,
            onOpenChangeComposer: { handle, text in orbModel.openChangeComposer(handle: handle, existingText: text) }
        )
        return VStack(spacing: 0) {
            RootTabContent(environment: environment, layout: layout, shared: shared)
            if environment.coordinator.selectedTab != .today {
                ConfirmationBar(decisions: environment.decisions)
                KitLineBar { environment.uploader.kitBar }.padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private var orbComposerInset: some View {
        switch orbModel.mode {
        case .attachmentPicker:
            AttachmentPickerSheet(
                onSelect: { orbModel.selectAttachment($0) },
                onDismiss: { orbModel.dismiss() }
            )
        case .keyboardComposer:
            DynamicComposerSheet(
                model: environment.typed,
                availability: environment.recording.recordAvailability,
                onRecordInstead: {
                    orbModel.dismiss()
                    present()
                },
                onDismiss: {
                    environment.typed.cancel()
                    orbModel.dismiss()
                }
            )
        case .idle, .radialOpen, .recording:
            EmptyView()
        }
    }

    private func recordingPanel(_ layout: RecordingPanelLayout) -> some View {
        RecordView(environment: environment, layout: layout)
            .frame(height: layout.panelHeight, alignment: .bottom)
    }

    private func bottomBar(_ layout: RecordingPanelLayout) -> some View {
        let availability = environment.recording.recordAvailability
        let screen = BottomBarScreen(inboxCount: environment.inbox.needsYouCount,
            availability: availability).presented(in: layout)
        let audit = environment.audit
        let identifier = audit?.stop.id == "xl-bottom-bar" ? audit?.stop.root : nil
        return BottomBarView(screen: screen, selected: environment.coordinator.selectedTab, select: select)
            .overlay(alignment: .top) {
                CaptureOrbView(model: orbModel, availability: availability, onStartVoice: present)
                    .offset(y: -12)
            }
            .auditRoot(identifier)
    }

    private func wireCallbacksAndAuditRoute() {
        environment.typed.onEditSubmit = { submission in await submitTileEdit(submission) }
        guard let auditStop = environment.audit?.stop else { return }
        switch auditStop.id {
        case "home-bento", "focus-modal":
            environment.coordinator.open(route: .tab(.home))
        case "home-radial-orb":
            environment.coordinator.open(route: .tab(.home))
            orbModel.longPressOrb()
        case "keyboard-composer":
            environment.coordinator.open(route: .tab(.home))
            orbModel.chooseRadial(.keyboard, availability: environment.recording.recordAvailability)
        case "inbox-universal-tiles":
            environment.coordinator.open(route: .tab(.inbox))
        case "tasks-ideas":
            environment.today.selectedSegment = 3
            environment.coordinator.open(route: .tab(.today))
        case "search-results":
            environment.coordinator.open(route: .search)
        default:
            break
        }
    }

    private func syncTypedContext(for mode: CaptureOrbMode) {
        if case .keyboardComposer(let context) = mode {
            environment.typed.apply(context: context)
        }
    }

    private func submitTileEdit(_ submission: ComposerEditSubmission) async {
        if let proposal = environment.inbox.snapshot?.proposals.first(where: { $0.handle == submission.handle }) {
            await environment.decisions.change(proposal, text: submission.text)
        } else {
            await environment.corrections.correct(handle: submission.handle, text: submission.text)
        }
        orbModel.dismiss()
    }

    private func handleScenePhase() async {
        guard environment.audit == nil else { return }
        if scenePhase == .active { await environment.loop.becameActive() }
        else { environment.loop.leftForeground() }
    }

    private func runLoop() async {
        while !Task.isCancelled, let delay = environment.loop.nextDelay() {
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled else { return }
            await environment.loop.tick()
        }
    }

    private func monitorRecording() async {
        while !Task.isCancelled {
            environment.recording.requestTick()
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
        }
    }

    private func present() {
        guard environment.recording.recordAvailability.isEnabled else { return }
        Task { await environment.recording.start() }
    }

    private func select(_ kind: BottomBarKind) {
        switch kind {
        case .home: environment.coordinator.open(route: .tab(.home))
        case .inbox: environment.coordinator.open(route: .tab(.inbox))
        case .tasks: environment.coordinator.open(route: .tab(.today))
        case .settings: environment.coordinator.open(route: .tab(.settings))
        case .record:
            orbModel.tapOrb(availability: environment.recording.recordAvailability)
            if orbModel.mode == .recording { present() }
        case .write: Task { await environment.openWrite() }
        }
    }
}

private struct RootTabContent: View {
    let environment: AppEnvironment
    let layout: RecordingPanelLayout
    let shared: RootSharedModels

    var body: some View {
        let activeFocus = shared.focusModel.activeFilter?.label
        switch environment.coordinator.selectedTab {
        case .home:
            homeContent(activeFocus: activeFocus)
        case .inbox:
            InboxView(
                environment: environment, activeFocus: activeFocus,
                framingStore: shared.framingStore, onOpenChangeComposer: shared.onOpenChangeComposer)
        case .today:
            TodayView(
                environment: environment, layout: layout,
                activeFocus: activeFocus, onOpenChangeComposer: shared.onOpenChangeComposer)
        case .settings:
            SettingsView(environment: environment, focusModel: shared.focusModel, framingStore: shared.framingStore)
        }
    }

    @ViewBuilder
    private func homeContent(activeFocus: String?) -> some View {
        switch environment.coordinator.activeRoute {
        case .brief:
            BriefView(
                environment: environment, focusModel: shared.focusModel,
                briefingAudio: shared.briefingAudio, onBackHome: { environment.coordinator.open(route: .tab(.home)) })
        case .search:
            TaskSearchView(
                environment: environment, activeFocus: activeFocus,
                framingStore: shared.framingStore, onOpenChangeComposer: shared.onOpenChangeComposer)
        case .tab:
            HomeView(
                environment: environment, focusModel: shared.focusModel,
                briefingAudio: shared.briefingAudio, actions: homeActions)
        }
    }

    private var homeActions: HomeActions {
        HomeActions(
            navigation: HomeNavigation(
                onOpenSettings: { environment.coordinator.open(route: .tab(.settings)) },
                onOpenSearch: { environment.coordinator.open(route: .search) },
                onOpenInbox: { environment.coordinator.open(route: .tab(.inbox)) }
            ),
            onOpenTasksBucket: { bucket in
                environment.today.selectedSegment = bucket.rawValue
                environment.coordinator.open(route: .tab(.today))
            },
            onOpenBrief: { environment.coordinator.open(route: .brief) }
        )
    }
}
