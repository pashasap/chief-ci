import SwiftUI
import UIKit
import Core

/// In-layout floating Liquid Glass drawer; recorder ownership remains in the environment's Core model.
struct RecordView: View {
    let environment: AppEnvironment
    let layout: RecordingPanelLayout

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @State private var dotVisible = true

    private var recording: RecordingModel { environment.recording }

    var body: some View {
        Group {
            if recording.isTypingInstead {
                DynamicComposerSheet(
                    model: environment.typed,
                    availability: recording.recordAvailability,
                    onRecordInstead: { _Concurrency.Task { await recording.recordInstead() } },
                    onDismiss: { recording.closeTypedPanel() })
                    .auditRoot(auditRoot(for: "independent-write"))
            } else {
                recordingBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private var recordingBody: some View {
        let base = RecordingScreen(model: recording).presented(in: layout)
        let screen = reduceMotion ? base.presented(in: layout, reduceMotion: true) : base
        return Group {
            if screen.contentScrollable {
                ScrollView { recordingStack(screen) }
            } else {
                recordingStack(screen)
            }
        }
        .liquidGlassTile(glow: .purple)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .auditRoot(recordingAuditRoot(screen))
        .confirmationDialog(
            screen.confirmation?.title ?? "", isPresented: confirmingBinding, titleVisibility: .visible
        ) {
            Button(screen.confirmation?.confirmLabel ?? "") {
                _Concurrency.Task { await recording.confirmTypeInstead() }
            }
            Button(screen.confirmation?.cancelLabel ?? "", role: .cancel) { recording.cancelTypeInstead() }
        }
    }

    private func auditRoot(for id: String) -> String? {
        guard let stop = environment.audit?.stop, stop.id == id else { return nil }
        return stop.root
    }

    private func recordingAuditRoot(_ screen: RecordingScreen) -> String? {
        if !screen.recoveryControls.isEmpty { return auditRoot(for: "permission-recovery") }
        guard screen.statusLabel != nil, environment.audit?.showsRecording == true else { return nil }
        return environment.audit?.stop.root
    }

    private func recordingStack(_ screen: RecordingScreen) -> some View {
        VStack(spacing: 12) {
            if screen.statusLabel != nil {
                headerRow(screen)
                RecordingMeter(level: screen.level, samples: screen.waveformSamples, reduceMotion: reduceMotion)
            } else if screen.savedText != nil {
                timer(screen)
            }
            lines(screen)
            footerRow(screen)
        }
        .padding(14)
    }

    private func headerRow(_ screen: RecordingScreen) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                statusRow(screen)
                Spacer(minLength: 8)
                timer(screen)
            }
            VStack(spacing: 4) {
                statusRow(screen)
                timer(screen)
            }
        }
    }

    private func timer(_ screen: RecordingScreen) -> some View {
        Text(screen.timerText)
            .font(screen.scalableText ? .title2.weight(.medium).monospacedDigit()
                : .system(size: 24, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.color(screen.foreground))
            .accessibilityLabel(screen.timerAccessibilityLabel)
            .fixedSize()
    }

    private var confirmingBinding: Binding<Bool> {
        Binding(
            get: { recording.isConfirmingTypeInstead },
            set: { if !$0 { recording.cancelTypeInstead() } })
    }

    private func statusRow(_ screen: RecordingScreen) -> some View {
        HStack(spacing: 8) {
            if let dot = screen.statusDot {
                Circle()
                    .fill(Theme.color(dot))
                    .frame(width: 10, height: 10)
                    .opacity(reduceMotion ? 1.0 : (dotVisible ? 1.0 : 0.25))
                    .onAppear { startBlink() }
                    .accessibilityHidden(true)
            }
            if let text = screen.statusLabel {
                Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.color(screen.foreground)).wrapping()
            }
        }
    }

    private func startBlink() {
        guard !reduceMotion else { dotVisible = true; return }
        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { dotVisible = false }
    }

    private func lines(_ screen: RecordingScreen) -> some View {
        VStack(spacing: 6) {
            if let preview = screen.livePreviewLine, screen.savedText == nil {
                Text(preview)
                    .font(.subheadline.italic())
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .wrapping()
            }
            ForEach([screen.savedText, screen.transcriptLine, screen.deliveryLine, screen.message].compactMap { $0 }, id: \.self) { line in
                Text(line).font(.subheadline).foregroundStyle(Theme.recordText).multilineTextAlignment(.center).wrapping()
            }
        }
    }

    private func footerRow(_ screen: RecordingScreen) -> some View {
        let activeControls = screen.recoveryFooterControls.isEmpty ? screen.footerControls : screen.recoveryFooterControls
        return HStack(spacing: 10) {
            ForEach(activeControls, id: \.label) { control in
                controlButton(control)
            }
        }
    }

    private func controlButton(_ control: RecordingControl) -> some View {
        let isPrimary = control.action == .stop || control.action == .done || control.action == .write
        return Button {
            perform(control.action)
        } label: {
            Text(control.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isPrimary ? Theme.primaryWhite : Theme.text)
                .wrapping()
                .frame(minWidth: control.minimumTarget, maxWidth: .infinity, minHeight: control.minimumTarget)
                .padding(.horizontal, 12)
                .background(buttonBackground(isPrimary: isPrimary))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Theme.primaryWhite.opacity(isPrimary ? 0.25 : 0.16), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(control.accessibilityLabel)
    }

    private func buttonBackground(isPrimary: Bool) -> some ShapeStyle {
        if isPrimary {
            return AnyShapeStyle(LinearGradient(
                colors: [Theme.glowCyan, Theme.glowBlue],
                startPoint: .leading, endPoint: .trailing))
        }
        return AnyShapeStyle(Theme.glassBaseMid.opacity(0.72))
    }

    private func perform(_ action: RecordingAction) {
        switch action {
        case .stop: _Concurrency.Task { await recording.stop() }
        case .discard: _Concurrency.Task { await recording.discard() }
        case .typeInstead, .write: _Concurrency.Task { await environment.openWrite() }
        case .done: recording.done()
        case .openSettings:
            if environment.audit == nil, let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        }
    }
}

private struct RecordingMeter: View {
    let level: Double
    let samples: [Double]
    let reduceMotion: Bool

    var body: some View {
        Group {
            if reduceMotion || samples.isEmpty { levelBar }
            else { waveform }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Microphone level")
        .accessibilityValue(level.formatted(.percent.precision(.fractionLength(0))))
    }

    private var levelBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.recordText.opacity(0.18))
                Capsule().fill(Theme.glowCyan).frame(width: proxy.size.width * level)
            }
        }
        .frame(height: 8)
    }

    private var waveform: some View {
        let bars = Array(samples.suffix(8))
        let padded = Array(repeating: max(0.12, level * 0.4), count: max(0, 8 - bars.count)) + bars
        return HStack(spacing: 6) {
            ForEach(Array(padded.enumerated()), id: \.offset) { _, sample in
                Capsule()
                    .fill(LinearGradient(colors: [Theme.glowCyan, Theme.glowPurple], startPoint: .bottom, endPoint: .top))
                    .frame(width: 6, height: max(6, 28 * CGFloat(sample)))
            }
        }
        .frame(height: 30)
    }
}
