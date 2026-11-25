import SwiftUI
import UIKit
import Core

struct HomeNavigation {
    var onOpenSettings: () -> Void
    var onOpenSearch: () -> Void
    var onOpenInbox: () -> Void

    init(
        onOpenSettings: @escaping () -> Void = {},
        onOpenSearch: @escaping () -> Void = {},
        onOpenInbox: @escaping () -> Void = {}
    ) {
        self.onOpenSettings = onOpenSettings
        self.onOpenSearch = onOpenSearch
        self.onOpenInbox = onOpenInbox
    }
}

struct HomeActions {
    var navigation: HomeNavigation
    var onOpenTasksBucket: (HomeHorizonBucket) -> Void
    var onOpenBrief: () -> Void

    init(
        navigation: HomeNavigation = HomeNavigation(),
        onOpenTasksBucket: @escaping (HomeHorizonBucket) -> Void = { _ in },
        onOpenBrief: @escaping () -> Void = {}
    ) {
        self.navigation = navigation
        self.onOpenTasksBucket = onOpenTasksBucket
        self.onOpenBrief = onOpenBrief
    }
}

/// Obsidian Liquid Glass Home Bento dashboard with inline Daily Briefing and AI Focus rings.
struct HomeView: View {
    let environment: AppEnvironment
    let focusModel: FocusFilterModel
    let briefingAudio: BriefingAudioModel
    let actions: HomeActions

    private let weatherModel: WeatherLocationModel = .shared
    private let weatherAdapter: LocationWeatherAdapter = .shared

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isFocusEditorOpen = false
    @State private var showLocationSettingsAlert = false

    init(
        environment: AppEnvironment,
        focusModel: FocusFilterModel,
        briefingAudio: BriefingAudioModel,
        actions: HomeActions = HomeActions()
    ) {
        self.environment = environment
        self.focusModel = focusModel
        self.briefingAudio = briefingAudio
        self.actions = actions
        _isFocusEditorOpen = State(initialValue: environment.audit?.stop.id == "focus-modal")
    }

    init(environment: AppEnvironment, actions: HomeActions = HomeActions()) {
        self.init(
            environment: environment,
            focusModel: FocusFilterModel(files: DirectoryFileStore(folderName: "chief")),
            briefingAudio: BriefingAudioModel(speech: BriefingAudioAdapter()),
            actions: actions
        )
    }

    private var screen: HomeScreen {
        HomeScreen(inbox: environment.inbox, focus: focusModel, clock: environment.clock)
    }

    var body: some View {
        let current = screen
        ZStack {
            AmbientScreenCanvas()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HomeHeroHeaderView(screen: current, actions: headerActions, weather: weatherModel)
                    needsAttentionCard(current)
                    briefingAndFocusRow(current)
                    horizonGrid(current)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .refreshable { await refreshHome() }
        }
        .task {
            guard environment.audit == nil else { return }
            weatherAdapter.refreshIfAuthorized()
        }
        .sheet(isPresented: $isFocusEditorOpen) {
            FocusEditorSheet(model: focusModel)
                .auditRoot(environment.audit?.stop.id == "focus-modal" ? "kit.audit.focus-modal" : nil)
        }
        .alert("Location Access Off", isPresented: $showLocationSettingsAlert) {
            Button("Open Settings") { weatherAdapter.openAppSettings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(weatherModel.statusCaption)
        }
    }

    private func refreshHome() async {
        await environment.inbox.pullToRefresh()
        if environment.audit == nil { weatherAdapter.refreshIfAuthorized() }
    }

    private func handleWeatherTap() {
        if weatherModel.permissionState == .denied {
            showLocationSettingsAlert = true
        } else {
            weatherAdapter.requestLocationAndRefresh()
        }
    }

    private var headerActions: HomeHeaderActions {
        HomeHeaderActions(
            onOpenSettings: actions.navigation.onOpenSettings,
            onOpenSearch: actions.navigation.onOpenSearch,
            onOpenInbox: actions.navigation.onOpenInbox,
            onOpenToday: { actions.onOpenTasksBucket(.today) },
            onClearFocus: { focusModel.clearFilter() },
            onTapWeather: handleWeatherTap
        )
    }

    private func needsAttentionCard(_ current: HomeScreen) -> some View {
        Button(action: actions.navigation.onOpenInbox) {
            HStack(spacing: 14) {
                Text("\(current.needsAttentionCount)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Theme.primaryWhite)
                    .frame(width: 40, height: 40)
                    .background(Theme.glowBlue, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Needs Attention")
                        .font(.headline)
                        .foregroundStyle(Theme.primaryWhite)
                    Text(current.needsAttentionSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .wrapping()
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: Theme.minimumTapTarget, alignment: .leading)
            .liquidGlassTile(glow: .blue)
            .contentShape(RoundedRectangle(cornerRadius: Theme.glassTileCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func briefingAndFocusRow(_ current: HomeScreen) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                dailyBriefingCard(current)
                FocusRingsBarView(model: focusModel) { isFocusEditorOpen = true }
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                dailyBriefingCard(current)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                FocusRingsBarView(model: focusModel) { isFocusEditorOpen = true }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func dailyBriefingCard(_ current: HomeScreen) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: actions.onOpenBrief) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Daily Briefing")
                            .font(.headline)
                            .foregroundStyle(Theme.primaryWhite)
                        Text(briefingAudio.statusLabel)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(briefingAudio.isPlaying ? Theme.glowTeal : Theme.secondaryText)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                playBriefingButton(script: current.briefScript)
                if briefingAudio.isPlaying {
                    EqualizerBarsView()
                } else {
                    Text("Open Brief")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.secondaryText)
                        .onTapGesture(perform: actions.onOpenBrief)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .liquidGlassTile(glow: .teal)
    }

    private func playBriefingButton(script: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            briefingAudio.togglePlayback(script: script)
        } label: {
            Image(systemName: briefingAudio.isPlaying ? "pause.fill" : "play.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primaryWhite)
                .frame(width: 40, height: 40)
                .liquidGlassCircle(tint: Theme.glowTeal)
                .frame(minWidth: Theme.minimumTapTarget, minHeight: Theme.minimumTapTarget)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(briefingAudio.isPlaying ? "Pause Daily Briefing" : "Play Daily Briefing")
    }

    private func horizonGrid(_ current: HomeScreen) -> some View {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: count)
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(HomeHorizonBucket.allCases, id: \.self) { bucket in
                horizonTile(current.summary(for: bucket))
            }
        }
    }

    private func horizonTile(_ summary: HomeHorizonSummary) -> some View {
        let style = bucketStyle(summary.bucket)
        return Button { actions.onOpenTasksBucket(summary.bucket) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(style.dot).frame(width: 8, height: 8)
                    Text(summary.title)
                        .font(.headline)
                        .foregroundStyle(Theme.primaryWhite)
                    Spacer()
                    Text("\(summary.count)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.text)
                }
                if summary.previews.isEmpty {
                    Text(summary.emptyText)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .wrapping()
                } else {
                    ForEach(Array(summary.previews.enumerated()), id: \.offset) { _, preview in
                        Text("• \(preview)")
                            .font(.caption)
                            .foregroundStyle(Theme.text.opacity(0.85))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .liquidGlassTile(glow: style.glow)
            .contentShape(RoundedRectangle(cornerRadius: Theme.glassTileCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(summary.title), \(summary.count) items")
    }

    private func bucketStyle(_ bucket: HomeHorizonBucket) -> (dot: Color, glow: GlassGlowTone) {
        switch bucket {
        case .today: return (Theme.glowAmber, .amber)
        case .later: return (Theme.indigoAccent, .purple)
        case .waiting: return (Theme.glowCyan, .cyan)
        case .ideas: return (Theme.glowBlue, .blue)
        }
    }
}

private struct EqualizerBarsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            bar(height: phase ? 14 : 6)
            bar(height: phase ? 8 : 16)
            bar(height: phase ? 15 : 9)
        }
        .frame(height: 16)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                phase = true
            }
        }
    }

    private func bar(height: CGFloat) -> some View {
        Capsule()
            .fill(Theme.glowTeal)
            .frame(width: 3, height: height)
    }
}
