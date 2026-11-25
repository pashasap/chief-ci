import SwiftUI
import Core

/// Home-only Daily Briefing detail view with ‹ Home capsule, audio player, Executive Focus, and screening signals.
struct BriefView: View {
    let environment: AppEnvironment
    let focusModel: FocusFilterModel
    let briefingAudio: BriefingAudioModel
    let onBackHome: () -> Void

    @State private var sheetHandle: String?

    init(
        environment: AppEnvironment,
        focusModel: FocusFilterModel,
        briefingAudio: BriefingAudioModel,
        onBackHome: @escaping () -> Void
    ) {
        self.environment = environment
        self.focusModel = focusModel
        self.briefingAudio = briefingAudio
        self.onBackHome = onBackHome
    }

    init(environment: AppEnvironment) {
        self.init(
            environment: environment,
            focusModel: FocusFilterModel(files: DirectoryFileStore(folderName: "chief")),
            briefingAudio: BriefingAudioModel(speech: BriefingAudioAdapter()),
            onBackHome: { environment.coordinator.open(route: .tab(.home)) }
        )
    }

    private var screen: BriefScreen { BriefScreen(inbox: environment.inbox) }

    var body: some View {
        let currentScreen = screen
        let brief = BriefPresentation(inbox: environment.inbox, clock: environment.clock, ideas: environment.today.ideas)
        ZStack {
            AmbientScreenCanvas()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    topBar(currentScreen)
                    headingBlock(brief)
                    listenButton(brief)
                    executiveFocusCard(currentScreen, brief: brief)
                    screeningSignalsCard(brief)
                    typedSectionsCard(brief)
                    resultsCard(currentScreen)
                    recordedCard(brief)
                }
                .padding(16)
            }
            .refreshable { await environment.inbox.pullToRefresh() }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: sheetOpen) {
            if let handle = sheetHandle { ResultSheetView(model: environment.resultSheet(handle: handle)) }
        }
    }

    private var sheetOpen: Binding<Bool> {
        Binding(get: { sheetHandle != nil }, set: { if !$0 { sheetHandle = nil } })
    }

    private func topBar(_ currentScreen: BriefScreen) -> some View {
        HStack {
            Button(action: onBackHome) {
                Label("Home", systemImage: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 14)
                    .frame(minHeight: Theme.minimumTapTarget)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(Theme.primaryWhite.opacity(0.2), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to Home")
            Spacer()
            if !currentScreen.updatedText.isEmpty {
                Text(currentScreen.updatedText)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .wrapping()
            }
        }
    }

    private func headingBlock(_ brief: BriefPresentation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Daily Briefing")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.glowTeal)
            Text(brief.liveDateHeading)
                .font(.largeTitle.weight(.light))
                .foregroundStyle(Theme.primaryWhite)
                .wrapping()
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func listenButton(_ brief: BriefPresentation) -> some View {
        let script = brief.audioScript(activeFocus: focusModel.activeFilter)
        return Button {
            briefingAudio.togglePlayback(script: script)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: briefingAudio.isPlaying ? "pause.fill" : "play.fill")
                    .foregroundStyle(Theme.primaryWhite)
                Text(briefingAudio.listenButtonLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryWhite)
                if briefingAudio.elapsedSeconds > 0 || briefingAudio.isPlaying {
                    Text(briefingAudio.statusLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.heroMid)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: Theme.minimumTapTarget)
            .background(
                LinearGradient(
                    colors: [Theme.glowTeal.opacity(0.65), Theme.accent.opacity(0.65)],
                    startPoint: .leading, endPoint: .trailing),
                in: Capsule())
            .overlay {
                Capsule().strokeBorder(Theme.primaryWhite.opacity(0.25), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func executiveFocusCard(_ currentScreen: BriefScreen, brief: BriefPresentation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Executive Focus")
                .font(.headline)
                .foregroundStyle(Theme.primaryWhite)
            Text(brief.executiveSummary)
                .font(.body)
                .foregroundStyle(Theme.text)
                .wrapping()
            ForEach(currentScreen.card, id: \.label) { line in
                HStack(alignment: .firstTextBaseline) {
                    Text(line.label)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    Text(line.value)
                        .font(.caption)
                        .foregroundStyle(line.isWarning ? Theme.amber : Theme.text)
                        .wrapping()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassTile(glow: .teal)
    }

    private func screeningSignalsCard(_ brief: BriefPresentation) -> some View {
        let signals = brief.focusScreeningSignals(activeFocus: focusModel.activeFilter, filters: focusModel.filters)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Focus Screening Signals")
                .font(.headline)
                .foregroundStyle(Theme.primaryWhite)
            ForEach(Array(signals.enumerated()), id: \.offset) { _, line in
                Text("• \(line)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.text.opacity(0.9))
                    .wrapping()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassTile(glow: .purple)
    }

    private func typedSectionsCard(_ brief: BriefPresentation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let cached = brief.cachedLabel { Text(cached).foregroundStyle(Theme.amber).wrapping() }
            Text("Snapshot " + brief.snapshotAge).font(.caption).foregroundStyle(Theme.secondaryText).wrapping()
            ForEach(brief.sections.filter { $0.kind != .results }, id: \.kind) { section in
                sectionBlock(section, brief: brief)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassTile(glow: .none)
    }

    private func sectionBlock(_ section: BriefSection, brief: BriefPresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Self.title(section.kind)).font(.headline).foregroundStyle(Theme.text)
            if let label = section.label { Text(label).font(.caption).foregroundStyle(Theme.secondaryText) }
            if let summary = section.summary { Text(summary).foregroundStyle(Theme.text).wrapping() }
            if let empty = section.emptyText { Text(empty).foregroundStyle(Theme.secondaryText).wrapping() }
            ForEach(section.rows, id: \.id) { row in
                rowBlock(row, brief: brief)
            }
        }
    }

    private func rowBlock(_ row: BriefRow, brief: BriefPresentation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.text).foregroundStyle(Theme.text).wrapping()
            if let because = row.because { Text(because).foregroundStyle(Theme.secondaryText).wrapping() }
            if let status = row.statusText { Text(status).font(.caption).foregroundStyle(Theme.secondaryText).wrapping() }
            ForEach(row.controls, id: \.action) { control in
                Button(control.label) { Task { await brief.perform(control) } }
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(!control.isEnabled)
            }
            if let details = row.detailsText {
                DisclosureGroup("More") { Text(details).font(.caption).foregroundStyle(Theme.secondaryText) }
            }
        }
    }

    private func recordedCard(_ brief: BriefPresentation) -> some View {
        let section = brief.recorded
        return VStack(alignment: .leading, spacing: 6) {
            Text(section.title).font(.headline).foregroundStyle(Theme.text)
            if let empty = section.emptyText { Text(empty).foregroundStyle(Theme.secondaryText).wrapping() }
            ShareButtons { section.shareControls(files: $0) }.id(section.text ?? "")
            if let text = section.text { Text(text).foregroundStyle(Theme.text).wrapping() }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassTile(glow: .none)
    }

    private func resultsCard(_ currentScreen: BriefScreen) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(currentScreen.resultsTitle) \(currentScreen.resultsCount)")
                .font(.headline).foregroundStyle(Theme.text)
            ForEach(currentScreen.results, id: \.handle) { row in
                Button { sheetHandle = row.handle } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title).foregroundStyle(Theme.text).wrapping()
                        Text(row.handle).font(.caption2).foregroundStyle(Theme.secondaryText)
                        Text(row.date).font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(row.title)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassTile(glow: .blue)
    }

    private static func title(_ kind: BriefSectionKind) -> String {
        switch kind {
        case .tasks: return "Due today"
        case .decisions: return "Decisions"
        case .proposals: return "Proposals"
        case .ideas: return "Ideas"
        case .worker: return "Worker"
        case .results: return "Results"
        }
    }
}
