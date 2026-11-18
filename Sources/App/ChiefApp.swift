import AVFoundation
import SwiftUI
import Core

@main
struct ChiefApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
                .onOpenURL { environment.coordinator.open(url: $0) }
        }
    }
}

struct RootView: View {
    let environment: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        GeometryReader { proxy in
            let layout = RecordingPanelLayout(width: proxy.size.width, height: proxy.size.height,
                largestText: textSize.isAccessibilitySize)
            VStack(spacing: 0) {
                content(layout).frame(maxWidth: .infinity, maxHeight: .infinity)
                if environment.recording.isPanelPresented {
                    recordingPanel(layout)
                }
                bottomBar(selected: environment.coordinator.selectedTab, layout: layout)
                    .frame(minHeight: layout.bottomBarHeight)
            }
        }
        .tint(Theme.accent)
        .task(id: scenePhase) {
            if scenePhase == .active { await environment.loop.becameActive() }
            else { environment.loop.leftForeground() }
        }
        .task(id: environment.loop.wakeKey) { await runLoop() }
        .task { await monitorRecording() }
        .task(id: environment.coordinator.recordRequested) {
            if environment.coordinator.consumeRecordRequest() { present() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in
            Task { await environment.recording.handleInterruption() }
        }
        .onChange(of: environment.recording.isPanelPresented) { _, presented in
            if !presented { Task { await environment.sync() } }
        }
    }

    private func content(_ layout: RecordingPanelLayout) -> some View {
        VStack(spacing: 0) {
            switch environment.coordinator.selectedTab {
            case .inbox: InboxView(environment: environment)
            case .today: TodayView(model: environment.today, inbox: environment.inbox, environment: environment,
                layoutSize: CGSize(width: layout.width, height: layout.height))
            case .brief: BriefView(environment: environment)
            case .settings: SettingsView(environment: environment)
            }
            ConfirmationBar(decisions: environment.decisions)
            KitLineBar { environment.uploader.kitBar }.padding(.horizontal, 16)
        }
    }

    private func recordingPanel(_ layout: RecordingPanelLayout) -> some View {
        let screen = RecordingScreen(model: environment.recording).presented(in: layout)
        return RecordView(environment: environment, layout: layout)
            .frame(height: layout.panelHeight, alignment: screen.anchor == .bottom ? .bottom : .center)
            .allowsHitTesting(screen.presentation == .nonmodal && screen.backgroundInteractionEnabled)
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
            // The saving task belongs to the model, not a panel or tab's task.
            environment.recording.requestTick()
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
        }
    }

    private func present() {
        guard environment.recording.recordAvailability.isEnabled else { return }
        environment.typed.reopen()
        Task { await environment.recording.start() }
    }

    @ViewBuilder private func bottomBar(selected: AppTab, layout: RecordingPanelLayout) -> some View {
        let availability: RecordAvailability = environment.recording.recordAvailability
        let screen = BottomBarScreen(inboxCount: environment.inbox.needsYouCount,
            availability: availability).presented(in: layout)
        if screen.usesCompactSizing {
            // Bound the fixed navigation chrome, not the Dynamic Type of the screen above it.
            barRow(selected, screen).dynamicTypeSize(...DynamicTypeSize.large)
        } else {
            barRow(selected, screen)
        }
    }

    private func barRow(_ selected: AppTab, _ screen: BottomBarScreen) -> some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(screen.items, id: \.kind) { item in
                if item.raised {
                    barButton(item, selected: selected, screen: screen)
                } else {
                    barButton(item, selected: selected, screen: screen).frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Theme.card.ignoresSafeArea(edges: .bottom))
    }

    private func barButton(_ item: BottomBarItem, selected: AppTab, screen: BottomBarScreen) -> some View {
        Button { select(item.kind) } label: {
            if item.raised {
                Image(systemName: item.symbol)
                    .font(.title)
                    .foregroundStyle(Theme.recordText)
                    .frame(width: item.size, height: item.size)
                    .background(Theme.color(item.tint), in: Circle())
            } else {
                VStack(spacing: item.badgeGap) {
                    HStack(spacing: item.badgeGap) {
                        Image(systemName: item.symbol)
                        if item.reservesBadgeSpace || item.badge != nil { badgeSlot(item.badge) }
                    }
                    tabLabel(item, screen)
                }
                .foregroundStyle(isSelected(item.kind, selected) ? Theme.accent : Theme.secondaryText)
                .frame(minWidth: screen.scalableText ? 46 : item.minimumWidth, minHeight: item.minimumHeight,
                    alignment: item.iconTopAligned ? .top : .center)
                .contentShape(Rectangle())
            }
        }
        .disabled(!item.isEnabled)
        .accessibilityLabel(item.accessibilityLabel)
    }

    @ViewBuilder private func tabLabel(_ item: BottomBarItem, _ screen: BottomBarScreen) -> some View {
        let label = Text(item.label)
            .font(.caption)
            .lineLimit(item.labelLineLimit)
            .minimumScaleFactor(screen.scalableText ? 0.65 : 1)
            .multilineTextAlignment(.center)
        if screen.usesCompactSizing {
            label.fixedSize(horizontal: true, vertical: false)
        } else {
            label.wrapping()
        }
    }

    @ViewBuilder private func badgeSlot(_ badge: String?) -> some View {
        Text(badge ?? "0")
            .font(.caption2.bold())
            .foregroundStyle(Theme.accent)
            .lineLimit(1)
            .opacity(badge == nil ? 0 : 1)
            .accessibilityHidden(true)
    }

    private func select(_ kind: BottomBarKind) {
        switch kind {
        case .inbox: environment.coordinator.selectedTab = .inbox
        case .today: environment.coordinator.selectedTab = .today
        case .brief: environment.coordinator.selectedTab = .brief
        case .settings: environment.coordinator.selectedTab = .settings
        case .record: present()
        }
    }

    private func isSelected(_ kind: BottomBarKind, _ selected: AppTab) -> Bool {
        switch kind {
        case .inbox: return selected == .inbox
        case .today: return selected == .today
        case .brief: return selected == .brief
        case .settings: return selected == .settings
        case .record: return false
        }
    }
}

extension View {
    /// Every control is at least 44 by 44 points.
    func touchTarget() -> some View {
        frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
    }

    /// Text wraps instead of clipping.
    func wrapping() -> some View {
        fixedSize(horizontal: false, vertical: true)
    }
}
