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
    @State private var showRecording = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let coordinator = environment.coordinator
        VStack(spacing: 0) {
            switch coordinator.selectedTab {
            case .inbox: InboxView(environment: environment)
            case .today: TodayView(model: environment.today, inbox: environment.inbox, environment: environment)
            case .brief: BriefView(environment: environment)
            case .settings: SettingsView(environment: environment)
            }
            ConfirmationBar(decisions: environment.decisions)
            KitLineBar { environment.uploader.kitBar }.padding(.horizontal, 16)
            bottomBar(selected: coordinator.selectedTab)
        }
        .tint(Theme.accent)
        .fullScreenCover(isPresented: $showRecording, onDismiss: { Task { await environment.sync() } }) {
            RecordView(environment: environment)
        }
        .task(id: scenePhase) {
            if scenePhase == .active { await environment.loop.becameActive() }
            else { environment.loop.leftForeground() }
        }
        .task(id: environment.loop.wakeKey) {
            while !Task.isCancelled, let delay = environment.loop.nextDelay() {
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard !Task.isCancelled else { return }
                await environment.loop.tick()
            }
        }
        .task(id: coordinator.recordRequested) {
            if coordinator.consumeRecordRequest() { present() }
        }
    }

    private func present() {
        environment.typed.reopen()
        showRecording = true
    }

    private func bottomBar(selected: AppTab) -> some View {
        HStack(alignment: .bottom) {
            ForEach(BottomBarScreen(inboxCount: environment.inbox.needsYouCount).items, id: \.kind) { item in
                barButton(item, selected: selected).frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .background(Theme.card.ignoresSafeArea(edges: .bottom))
    }

    private func barButton(_ item: BottomBarItem, selected: AppTab) -> some View {
        Button {
            switch item.kind {
            case .inbox: environment.coordinator.selectedTab = .inbox
            case .today: environment.coordinator.selectedTab = .today
            case .brief: environment.coordinator.selectedTab = .brief
            case .settings: environment.coordinator.selectedTab = .settings
            case .record: present()
            }
        } label: {
            if item.raised {
                Image(systemName: "mic.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white)
                    .frame(width: item.size, height: item.size)
                    .background(Theme.recordButton, in: Circle())
                    .shadow(radius: 4, y: 2)
                    .offset(y: -12)
            } else {
                VStack(spacing: 2) {
                    Image(systemName: icon(item.kind))
                    HStack(spacing: 4) {
                        Text(item.label).font(.caption)
                        if let badge = item.badge { Text(badge).font(.caption.bold()).foregroundStyle(Theme.accent) }
                    }
                }
                .foregroundStyle(isSelected(item.kind, selected) ? Theme.accent : Theme.secondaryText)
                .frame(minWidth: item.size, minHeight: item.size)
            }
        }
        .accessibilityLabel(item.accessibilityLabel)
    }

    private func icon(_ kind: BottomBarKind) -> String {
        switch kind {
        case .inbox: return "tray"
        case .today: return "checklist"
        case .brief: return "doc.text"
        case .settings: return "gearshape"
        case .record: return "mic.fill"
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
