import SwiftUI
import UIKit
import Core

struct SettingsView: View {
    let environment: AppEnvironment
    @State private var link = ""
    @State private var confirmingUnpair = false

    private var model: SettingsModel { environment.settings }
    private var screen: SettingsScreen { SettingsScreen(model: model) }

    var body: some View {
        NavigationStack {
            List {
                statusSection
                pairingSection
                Section {
                    ForEach(screen.controls.filter { $0.action != .pasteLink }, id: \.label) { control in
                        controlButton(control)
                    }
                    if let result = screen.checkResult {
                        Text(result).foregroundStyle(Theme.text).wrapping()
                    }
                }
                remindersSection
                diagnosticsSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(screen.title)
            .task { await model.opened() }
            .confirmationDialog(screen.unpairTitle, isPresented: $confirmingUnpair) {
                Button(screen.unpairLabel, role: .destructive) { model.unpair() }
                Button(screen.cancelLabel, role: .cancel) {}
            } message: {
                Text(screen.unpairExplanation)
            }
            .task(id: environment.coordinator.pendingPairLink) { await pairFromLink() }
        }
    }

    private var statusSection: some View {
        Section(screen.statusTitle) {
            ForEach(screen.entries, id: \.label) { entry in
                LabeledContent {
                    Text(entry.value).foregroundStyle(Theme.text).wrapping()
                } label: {
                    Text(entry.label).foregroundStyle(Theme.text)
                }
                .frame(minHeight: 44, alignment: .leading)
            }
            if let explanation = screen.explanation {
                Text(explanation).foregroundStyle(Theme.amber).wrapping()
            }
        }
    }

    private var remindersSection: some View {
        let section = screen.reminders
        return Section(section.title) {
            Toggle(section.switchLabel, isOn: Binding(get: { section.isOn }, set: { enabled in
                _Concurrency.Task { await environment.reminders.setBriefReminder(on: enabled) }
            })).frame(minHeight: 44)
            if let status = section.statusText { Text(status).foregroundStyle(Theme.amber).wrapping() }
            ForEach(section.entries, id: \.label) { entry in
                LabeledContent { Text(entry.value).wrapping() } label: { Text(entry.label).wrapping() }
            }
        }
    }

    private var diagnosticsSection: some View {
        Section(screen.diagnostics.title) {
            ForEach(screen.diagnostics.rows, id: \.label) { entry in
                LabeledContent {
                    Text(entry.value).foregroundStyle(Theme.text).wrapping()
                } label: {
                    Text(entry.label).foregroundStyle(Theme.text)
                }
                .frame(minHeight: 44, alignment: .leading)
            }
            controlButton(screen.diagnostics.copyControl)
        }
    }

    private func controlButton(_ control: SettingsControl) -> some View {
        Button(control.label, role: control.role == .destructive ? .destructive : nil) {
            perform(control.action)
        }
        .disabled(!control.isEnabled)
        .touchTarget()
        .accessibilityLabel(control.label)
    }

    private func perform(_ action: SettingsAction) {
        switch action {
        case .pasteLink: link = UIPasteboard.general.string ?? link
        case .checkServer: _Concurrency.Task { await model.checkServer() }
        case .unpair: confirmingUnpair = true
        case .copyDiagnostics: model.copyDiagnostics(to: PasteboardClipboard())
        }
    }

    private var pairingSection: some View {
        Section(screen.pairTitle) {
            TextField(screen.pairingLinkLabel, text: $link, axis: .vertical)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .frame(minHeight: 44)
                .accessibilityLabel(screen.pairingLinkLabel)
            ForEach(screen.controls.filter { $0.action == .pasteLink }, id: \.label) { control in
                controlButton(control)
            }
            Button(screen.pairTitle) { _Concurrency.Task { await model.pasteLink(link) } }
                .touchTarget()
                .accessibilityLabel(screen.pairLinkHint)
            if let message = model.message {
                Text(message).foregroundStyle(Theme.amber).wrapping()
            }
        }
    }

    private func pairFromLink() async {
        guard let pending = environment.coordinator.consumePairLink() else { return }
        link = pending
        await model.pasteLink(pending)
    }
}
