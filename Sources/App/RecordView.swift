import AVFoundation
import SwiftUI
import Core

/// Full-screen recording over everything. Renders RecordingScreen and TypedCaptureScreen only.
struct RecordView: View {
    let environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    private var recording: RecordingModel { environment.recording }

    var body: some View {
        Group {
            if recording.isTypingInstead {
                TypedCaptureView(model: environment.typed, recordInstead: {
                    _Concurrency.Task { await recording.recordInstead() }
                }) { dismiss() }
            } else {
                recordingBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.recordBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task { await recording.start() }
        .task(id: recording.isClosed) { await tickWhileRecording() }
        .onChange(of: recording.isClosed) { _, closed in
            if closed && !recording.isTypingInstead { dismiss() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in
            _Concurrency.Task { await recording.handleInterruption() }
        }
    }

    private var recordingBody: some View {
        let screen = RecordingScreen(model: recording)
        return ScrollView {
        VStack(spacing: 20) {
            if let status = screen.statusLabel { statusRow(status) }
            Text(screen.timerText)
                .font(.system(size: 56, weight: .light, design: .monospaced))
                .foregroundStyle(Theme.recordText)
                .accessibilityLabel("Recording time \(screen.timerText)")
            LevelBar(level: screen.level)
            lines(screen)
            Spacer(minLength: 0)
            ForEach(screen.controls, id: \.label) { control in
                if control.action == .discard { Spacer(minLength: 20) }
                controlButton(control)
            }
        }
        .padding()
        }
        .confirmationDialog(
            screen.confirmation?.title ?? "", isPresented: confirmingBinding, titleVisibility: .visible
        ) {
            Button(screen.confirmation?.confirmLabel ?? "") {
                _Concurrency.Task { await recording.confirmTypeInstead() }
            }
            Button(screen.confirmation?.cancelLabel ?? "", role: .cancel) { recording.cancelTypeInstead() }
        }
    }

    private var confirmingBinding: Binding<Bool> {
        Binding(
            get: { recording.isConfirmingTypeInstead },
            set: { if !$0 { recording.cancelTypeInstead() } })
    }

    private func statusRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.recordButton).frame(width: 10, height: 10).accessibilityHidden(true)
            Text(text).foregroundStyle(Theme.recordText)
        }
    }

    private func lines(_ screen: RecordingScreen) -> some View {
        VStack(spacing: 6) {
            ForEach(
                [screen.savedText, screen.transcriptLine, screen.deliveryLine, recording.message]
                    .compactMap { $0 }, id: \.self
            ) { line in
                Text(line).foregroundStyle(Theme.recordText).multilineTextAlignment(.center).wrapping()
            }
        }
    }

    private func controlButton(_ control: RecordingControl) -> some View {
        Button {
            perform(control.action)
        } label: {
            Text(control.label)
                .frame(maxWidth: control.isFullWidth ? .infinity : nil, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(control.isFullWidth ? Theme.recordButton : .gray)
        .accessibilityLabel(control.label)
    }

    private func perform(_ action: RecordingAction) {
        switch action {
        case .stop: _Concurrency.Task { await recording.stop() }
        case .discard: _Concurrency.Task { await recording.discard() }
        case .typeInstead: recording.requestTypeInstead()
        case .done:
            recording.done()
            dismiss()
        }
    }

    private func tickWhileRecording() async {
        while !Task.isCancelled, !recording.isClosed {
            await recording.tick()
            try? await _Concurrency.Task.sleep(for: .milliseconds(200))
        }
    }
}

private struct LevelBar: View {
    let level: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.recordText.opacity(0.2))
                Capsule().fill(Theme.recordButton).frame(width: proxy.size.width * level)
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

private struct TypedCaptureView: View {
    let model: TypedCaptureModel
    let recordInstead: () -> Void
    let close: () -> Void
    @FocusState private var focused: Bool
    private var text: Binding<String> {
        Binding(get: { model.text }, set: { model.text = $0 })
    }

    var body: some View {
        let screen = TypedCaptureScreen(model: model, text: model.text)
        ScrollView {
        VStack(spacing: 16) {
            Text(screen.title).foregroundStyle(Theme.recordText).wrapping()
            TextField(screen.placeholder, text: text, axis: .vertical)
                .focused($focused)
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.recordText)
                .frame(minHeight: 120, alignment: .topLeading)
                .accessibilityLabel(screen.placeholder)
            if let message = screen.message {
                Text(message).foregroundStyle(Theme.recordText).wrapping()
            }
            ForEach(screen.controls, id: \.label) { control in
                Button(control.label) { perform(control.action) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!control.isEnabled)
                    .touchTarget()
                    .accessibilityLabel(control.label)
                    .accessibilityHint(control.disabledReason ?? "")
            }
        }
        .padding()
        }
        .task { focused = true }
        .onChange(of: model.isClosed) { _, closed in if closed { close() } }
    }

    private func perform(_ action: TypedCaptureAction) {
        switch action {
        case .save: model.save(text: model.text)
        case .cancel: model.cancel()
        case .recordInstead: recordInstead()
        }
    }
}
