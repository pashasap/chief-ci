import AVFoundation
import SwiftUI
import Core

/// In-layout panel; recorder ownership remains in the environment's Core model.
struct RecordView: View {
    let environment: AppEnvironment
    var layout: RecordingPanelLayout = RecordingPanelLayout(width: 390, height: 844, largestText: false)
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize: CGFloat = 56

    private var recording: RecordingModel { environment.recording }

    var body: some View {
        Group {
            if recording.isTypingInstead {
                TypedCaptureView(model: environment.typed, recordInstead: {
                    _Concurrency.Task { await recording.recordInstead() }
                }) { recording.closeTypedPanel() }
            } else {
                recordingBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.color(RecordingScreen(model: recording).background))
    }

    private var recordingBody: some View {
        let screen = RecordingScreen(model: recording).presented(in: layout)
        return Group {
            if screen.contentScrollable {
                ScrollView { recordingStack(screen) }
            } else {
                recordingStack(screen)
            }
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

    private func recordingStack(_ screen: RecordingScreen) -> some View {
        VStack(spacing: 20) {
            if screen.statusLabel != nil { statusRow(screen) }
            Text(screen.timerText)
                .font(screen.scalableText ? .system(size: timerSize, weight: .light, design: .monospaced)
                    : .largeTitle.weight(.light).monospacedDigit())
                .foregroundStyle(Theme.recordText)
                .accessibilityLabel(screen.timerAccessibilityLabel)
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

    private var confirmingBinding: Binding<Bool> {
        Binding(
            get: { recording.isConfirmingTypeInstead },
            set: { if !$0 { recording.cancelTypeInstead() } })
    }

    private func statusRow(_ screen: RecordingScreen) -> some View {
        HStack(spacing: 8) {
            if let dot = screen.statusDot {
                Circle().fill(Theme.color(dot)).frame(width: 10, height: 10).accessibilityHidden(true)
            }
            if let text = screen.statusLabel { Text(text).foregroundStyle(Theme.color(screen.foreground)) }
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
                .wrapping()
                .frame(maxWidth: control.isFullWidth ? .infinity : nil, minHeight: control.minimumTarget)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.color(control.tint))
        .accessibilityLabel(control.accessibilityLabel)
    }

    private func perform(_ action: RecordingAction) {
        switch action {
        case .stop: _Concurrency.Task { await recording.stop() }
        case .discard: _Concurrency.Task { await recording.discard() }
        case .typeInstead: recording.requestTypeInstead()
        case .done: recording.done()
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
