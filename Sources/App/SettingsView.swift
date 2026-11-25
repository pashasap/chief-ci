import SwiftUI
import UniformTypeIdentifiers
import UIKit
import Core

struct DiagnosticsExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .plainText] }
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Grouped Obsidian Liquid Glass Settings: Host & Sync, AI Focus Screening, Capture & Reminders.
struct SettingsView: View {
    let environment: AppEnvironment
    let focusModel: FocusFilterModel
    let framingStore: FramingSignalStore
    let weatherModel: WeatherLocationModel

    @AppStorage("chief.reminders.briefTime") private var briefTimeText = "07:40"
    @State private var link = ""
    @State private var greetingDraft = ""
    @State private var confirmingUnpair = false
    @State private var showOutboxDetails = false
    @State private var showFocusEditor = false
    @State private var exportingDiagnostics = false
    @State private var exportDocument = DiagnosticsExportDocument(data: Data())
    @State private var exportNotice: String?

    init(
        environment: AppEnvironment,
        focusModel: FocusFilterModel = FocusFilterModel(files: DirectoryFileStore(folderName: "chief")),
        framingStore: FramingSignalStore = .shared,
        weatherModel: WeatherLocationModel = .shared
    ) {
        self.environment = environment
        self.focusModel = focusModel
        self.framingStore = framingStore
        self.weatherModel = weatherModel
    }

    private var model: SettingsModel { environment.settings }
    private var screen: SettingsScreen {
        SettingsScreen(
            model: model,
            framingSignalCount: framingStore.entries.count,
            selectedVoice: BriefingAudioAdapter.selectedVoiceCandidate(),
            weather: weatherModel
        )
    }

    var body: some View {
        let current = screen
        ZStack {
            AmbientScreenCanvas()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(current)
                    greetingCard(current)
                    hostSyncCard(current)
                    SettingsFocusCard(screen: current, focusModel: focusModel) { showFocusEditor = true }
                    captureAndRemindersCard(current)
                    if showOutboxDetails { diagnosticsDetailCard(current) }
                    SettingsPairingCard(screen: current, model: model, link: $link)
                    footer(current)
                }
                .padding(16)
            }
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await model.checkServer() }
            .task { await openedSettings() }
            .confirmationDialog(current.unpairTitle, isPresented: $confirmingUnpair) {
                Button(current.unpairLabel, role: .destructive) { model.unpair() }
                Button(current.cancelLabel, role: .cancel) {}
            } message: { Text(current.unpairExplanation) }
            .task(id: environment.coordinator.pendingPairLink) { await pairFromLink() }
            .sheet(isPresented: $showFocusEditor) { FocusEditorSheet(model: focusModel) }
            .fileExporter(
                isPresented: $exportingDiagnostics, document: exportDocument,
                contentType: .json, defaultFilename: "kit-diagnostics.json"
            ) { result in
                if case .failure = result { exportNotice = "Diagnostics export could not be saved." }
                else { exportNotice = "Diagnostics exported." }
            }
        }
    }

    private func openedSettings() async {
        await model.opened()
        if environment.audit == nil {
            LocationWeatherAdapter.shared.refreshIfAuthorized()
        }
    }

    private func header(_ current: SettingsScreen) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(current.eyebrow).font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(Theme.accent)
            Text(current.title).font(.largeTitle.bold()).foregroundStyle(Theme.primaryWhite)
                .wrapping().accessibilityAddTraits(.isHeader)
        }
    }

    private func greetingCard(_ current: SettingsScreen) -> some View {
        TextField(current.greetingNameLabel, text: greetingNameBinding)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .padding(12)
            .background(Theme.surfaceDeep.opacity(0.65), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(minHeight: Theme.minimumTapTarget)
            .accessibilityLabel(current.greetingNameLabel)
            .padding(16).liquidGlassTile(glow: .none)
            .onAppear { greetingDraft = current.greetingName }
    }

    private var greetingNameBinding: Binding<String> {
        Binding(
            get: { greetingDraft },
            set: { newValue in
                greetingDraft = newValue
                model.setGreetingName(newValue)
            })
    }

    private func hostSyncCard(_ current: SettingsScreen) -> some View {
        let host = current.hostSummary
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(current.hostSectionTitle).font(.headline).foregroundStyle(Theme.primaryWhite)
                Spacer()
                Text(host.statusText).font(.caption.weight(.semibold))
                    .foregroundStyle(host.isPaired ? Theme.emeraldApprove : Theme.amber)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Theme.primaryWhite.opacity(0.08), in: Capsule())
            }
            LabeledContent("Server", value: host.serverHost).foregroundStyle(Theme.text)
            Button { showOutboxDetails.toggle() } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Outbox & Diagnostics").font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                        Text("Queued: \(host.pendingQueueCount) · Snapshot: \(host.lastSnapshotText) · Framing: \(host.framingSignalCount)")
                            .font(.caption).foregroundStyle(Theme.secondaryText).wrapping()
                    }
                    Spacer()
                    Image(systemName: showOutboxDetails ? "chevron.up" : "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                }.frame(minHeight: Theme.minimumTapTarget)
            }.buttonStyle(.plain)
            hostActionRow(current)
            if let result = current.checkResult { Text(result).font(.footnote).foregroundStyle(Theme.secondaryText).wrapping() }
            if let notice = exportNotice { Text(notice).font(.footnote).foregroundStyle(Theme.glowTeal).wrapping() }
        }.padding(16).liquidGlassTile(glow: .blue)
    }

    private func hostActionRow(_ current: SettingsScreen) -> some View {
        HStack(spacing: 10) {
            if let check = current.controls.first(where: { $0.action == .checkServer }) {
                pillButton(check.label, tint: Theme.accent, enabled: check.isEnabled) { _Concurrency.Task { await model.checkServer() } }
            }
            if let unpair = current.controls.first(where: { $0.action == .unpair }), unpair.isEnabled {
                pillButton(unpair.label, tint: Theme.roseReject, enabled: true) { confirmingUnpair = true }
            }
            pillButton("Export Diagnostics", tint: Theme.glowTeal, enabled: true) {
                exportDocument = DiagnosticsExportDocument(data: current.diagnosticsExportData(framingSummary: framingStore.exportSummary()) ?? Data())
                exportingDiagnostics = true
            }
        }
    }

    private func captureAndRemindersCard(_ current: SettingsScreen) -> some View {
        let cap = current.captureSummary
        let rem = current.reminders
        return VStack(alignment: .leading, spacing: 12) {
            Text(current.captureSectionTitle).font(.headline).foregroundStyle(Theme.primaryWhite)
            LabeledContent("Orb Long-Press Radial", value: cap.radialSummary).foregroundStyle(Theme.text)
            LabeledContent("On-Device Speech", value: "\(cap.speechLocale) · \(cap.speechAvailable ? "Ready" : "Unavailable")")
                .foregroundStyle(Theme.text)
            LabeledContent("Briefing Voice", value: cap.briefingVoiceLabel).foregroundStyle(Theme.text)
            if let voiceHint = cap.briefingVoiceHint {
                Text(voiceHint).font(.caption).foregroundStyle(Theme.amber).wrapping()
            }
            locationWeatherRow(cap)
            Toggle(rem.switchLabel, isOn: Binding(get: { rem.isOn }, set: { enabled in
                _Concurrency.Task { await environment.reminders.setBriefReminder(on: enabled) }
            })).tint(Theme.accent).frame(minHeight: Theme.minimumTapTarget)
            DatePicker("Brief reminder time", selection: briefTimeBinding, displayedComponents: .hourAndMinute)
                .foregroundStyle(Theme.text).frame(minHeight: Theme.minimumTapTarget)
            if let status = rem.statusText { Text(status).font(.footnote).foregroundStyle(Theme.amber).wrapping() }
            ForEach(rem.entries, id: \.label) { entry in
                LabeledContent(entry.label, value: entry.value).foregroundStyle(Theme.secondaryText)
            }
        }.padding(16).liquidGlassTile(glow: .purple)
    }

    private func locationWeatherRow(_ cap: SettingsCaptureSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Location & Weather").foregroundStyle(Theme.text)
                Spacer()
                pillButton(locationActionTitle(cap.locationPermissionState), tint: Theme.glowCyan, enabled: cap.locationPermissionState != .unavailable) {
                    LocationWeatherAdapter.shared.requestLocationAndRefresh()
                }
            }
            Text(cap.weatherStatusLabel).font(.caption.weight(.medium)).foregroundStyle(Theme.glowCyan)
            if let hint = cap.weatherHint {
                Text(hint).font(.caption).foregroundStyle(Theme.secondaryText).wrapping()
            }
        }
    }

    private func locationActionTitle(_ state: LocationPermissionState) -> String {
        switch state {
        case .notDetermined: return "Enable"
        case .authorized: return "Refresh"
        case .denied: return "Open Settings"
        case .unavailable: return "Unavailable"
        }
    }

    private func diagnosticsDetailCard(_ current: SettingsScreen) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(current.diagnostics.title).font(.headline).foregroundStyle(Theme.primaryWhite)
            ForEach(current.diagnostics.rows + current.diagnostics.health, id: \.label) { entry in
                LabeledContent(entry.label) { Text(entry.value).font(.footnote).foregroundStyle(Theme.secondaryText).wrapping() }
                    .foregroundStyle(Theme.text)
            }
            pillButton(current.diagnostics.copyControl.label, tint: Theme.accent, enabled: true) {
                model.copyDiagnostics(to: PasteboardClipboard())
            }
        }.padding(16).liquidGlassTile(glow: .none)
    }

    private func footer(_ current: SettingsScreen) -> some View {
        Text(current.versionFooter).font(.footnote.monospacedDigit()).foregroundStyle(Theme.secondaryText)
            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
    }

    private func pillButton(_ title: String, tint: Color, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(enabled ? tint : Theme.secondaryText)
                .padding(.horizontal, 12).padding(.vertical, 8).frame(minHeight: Theme.minimumTapTarget)
                .background(Theme.primaryWhite.opacity(0.08), in: Capsule())
        }.buttonStyle(.plain).disabled(!enabled)
    }

    private var briefTimeBinding: Binding<Date> {
        Binding(get: { Self.dateFromClock(briefTimeText) }, set: { briefTimeText = Self.clockFromDate($0) })
    }

    private static func dateFromClock(_ raw: String) -> Date {
        let parts = raw.split(separator: ":")
        let hour = parts.count == 2 ? (Int(parts[0]) ?? 7) : 7
        let minute = parts.count == 2 ? (Int(parts[1]) ?? 40) : 40
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    private static func clockFromDate(_ date: Date) -> String {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", comps.hour ?? 7, comps.minute ?? 40)
    }

    private func pairFromLink() async {
        guard let pending = environment.coordinator.consumePairLink() else { return }
        link = pending
        await model.pasteLink(pending)
    }
}

private struct SettingsFocusCard: View {
    let screen: SettingsScreen
    let focusModel: FocusFilterModel
    let onAddFocus: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(screen.focusSectionTitle).font(.headline).foregroundStyle(Theme.primaryWhite)
            ForEach(focusModel.filters) { filter in focusRow(filter) }
            Button(action: onAddFocus) {
                Label("Add AI-Screened Focus", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.glowTeal)
                    .frame(maxWidth: .infinity, minHeight: Theme.minimumTapTarget, alignment: .leading)
            }.buttonStyle(.plain)
        }.padding(16).liquidGlassTile(glow: .teal)
    }

    private func focusRow(_ filter: FocusFilter) -> some View {
        HStack(spacing: 12) {
            Image(systemName: filter.iconName).font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.color(filter.tokenColor)).frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(filter.label).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                Text(filter.purpose).font(.caption).foregroundStyle(Theme.secondaryText).wrapping()
            }
            Spacer()
            if !filter.isBuiltIn {
                Button(role: .destructive) { focusModel.removeCustomFocus(id: filter.id) } label: {
                    Image(systemName: "trash").font(.subheadline).foregroundStyle(Theme.roseReject)
                        .frame(minWidth: Theme.minimumTapTarget, minHeight: Theme.minimumTapTarget)
                }.buttonStyle(.plain).accessibilityLabel("Remove \(filter.label)")
            }
        }
    }
}

private struct SettingsPairingCard: View {
    let screen: SettingsScreen
    let model: SettingsModel
    @Binding var link: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(screen.pairTitle).font(.headline).foregroundStyle(Theme.primaryWhite)
            if let explanation = screen.explanation { Text(explanation).font(.footnote).foregroundStyle(Theme.amber).wrapping() }
            TextField(screen.pairingLinkLabel, text: $link, axis: .vertical)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .padding(12).background(Theme.surfaceDeep.opacity(0.65), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(minHeight: Theme.minimumTapTarget).accessibilityLabel(screen.pairingLinkLabel)
            if let paste = screen.controls.first(where: { $0.action == .pasteLink }) {
                Button(paste.label) { link = UIPasteboard.general.string ?? link }
                    .touchTarget().frame(maxWidth: .infinity, alignment: screen.pasteLinkAlignment == .leading ? .leading : .center)
            }
            Button(screen.pairTitle) { _Concurrency.Task { await model.pasteLink(link) } }
                .touchTarget().frame(maxWidth: .infinity, alignment: screen.pairAlignment == .leading ? .leading : .center)
                .accessibilityLabel(screen.pairLinkHint)
            if let message = model.message { Text(message).font(.footnote).foregroundStyle(Theme.amber).wrapping() }
        }.padding(16).liquidGlassTile(glow: .none)
    }
}
