import Foundation
import Observation

@MainActor
@Observable
public final class RecordingModel {
    public static let maxSeconds: TimeInterval = 600
    public static let busyText = "Still transcribing the last capture. Try again in a moment."

    public var vocabulary: [String] = []
    public private(set) var isStarting = false
    public private(set) var isTranscribing = false
    public private(set) var confirmingDiscard = false
    private var lastSavedId: String?
    private var closeAt: Date?
    public private(set) var isRecording = false
    public private(set) var savedMessage: String?
    public private(set) var message: String?
    public private(set) var transcript = ""
    public private(set) var timerText = "0:00"
    public private(set) var isDelivered = false
    public private(set) var isClosed = false
    public private(set) var isConfirmingTypeInstead = false
    public private(set) var isTypingInstead = false

    /// The recorder reading clamped to 0...1.
    public var level: Double {
        min(1, max(0, pipeline.recorder.level))
    }

    @ObservationIgnored private let store: OutboxStore
    @ObservationIgnored private let environment: RecordingEnvironment
    @ObservationIgnored private let pipeline: RecordingPipeline
    @ObservationIgnored private let osMajor: Int
    @ObservationIgnored private var clientId: String?

    public init(
        store: OutboxStore, environment: RecordingEnvironment, pipeline: RecordingPipeline, osMajor: Int
    ) {
        self.store = store
        self.environment = environment
        self.pipeline = pipeline
        self.osMajor = osMajor
    }

    public var recordAvailability: RecordAvailability {
        RecordAvailability(isEnabled: !isRecording && !isStarting && !isTranscribing && !store.hasPendingCapture)
    }

    public var isPanelPresented: Bool {
        isTypingInstead || (!isClosed && (isStarting || isRecording || savedMessage != nil || message != nil))
    }

    public func closeTypedPanel() {
        isTypingInstead = false
        isClosed = true
    }

    public func start() async {
        guard recordAvailability.isEnabled else { return }
        isStarting = true
        defer { isStarting = false }
        await beginRecording()
    }

    private func beginRecording() async {
        resetPresentation()
        let id = environment.ids.next().uuidString.lowercased()
        guard persistStart(id) else { return }
        await startRecorder(id)
    }

    private func resetPresentation() {
        lastSavedId = nil
        closeAt = nil
        message = nil
        savedMessage = nil
        transcript = ""
        timerText = TimerFormat.text(0)
        isDelivered = false
        isClosed = false
        isConfirmingTypeInstead = false
        isTypingInstead = false
        confirmingDiscard = false
    }

    private func persistStart(_ id: String) -> Bool {
        do {
            try store.save(.voice(clientId: id, recordedAt: environment.clock.now, durationS: 0))
            return true
        } catch {
            message = "Could not save this recording"
            return false
        }
    }

    private func startRecorder(_ id: String) async {
        pipeline.uploader.recordingId = id
        do {
            try await pipeline.recorder.start(clientId: id)
        } catch {
            store.remove(clientId: id)
            pipeline.uploader.recordingId = nil
            isRecording = false
            message = (error as? RecorderError) == .permissionDenied
                ? "Microphone not allowed" : "Could not start recording"
            return
        }
        guard !isClosed else {
            await pipeline.recorder.cancel()
            store.remove(clientId: id)
            pipeline.uploader.recordingId = nil
            return
        }
        isRecording = true
        clientId = id
        environment.lease.begin()
        environment.haptics.recordingStarted()
    }

    @ObservationIgnored private var tickTask: Task<Void, Never>?

    /// An unstructured model-owned task survives panel removal and tab navigation.
    public func requestTick() {
        guard tickTask == nil else { return }
        tickTask = Task { [self] in
            await tick()
            tickTask = nil
        }
    }

    public func tick() async {
        updateDelivery()
        if let closeAt, environment.clock.now >= closeAt { isClosed = true }
        guard isRecording else { return }
        let elapsed = pipeline.recorder.elapsed
        timerText = TimerFormat.text(elapsed)
        if elapsed >= Self.maxSeconds { await stop() }
    }

    public func handleInterruption() async {
        await stop()
    }

    public func stop() async {
        guard isRecording, let id = clientId else { return }
        isRecording = false
        clientId = nil
        let duration = pipeline.recorder.elapsed
        // Keep this capture protected until transcription has persisted its final metadata.
        defer {
            if !isRecording { environment.lease.end() }
            if pipeline.uploader.recordingId == id { pipeline.uploader.recordingId = nil }
        }
        isConfirmingTypeInstead = false
        let audio: Data
        do {
            audio = try await pipeline.recorder.stop()
            try store.saveAudio(audio, clientId: id)
        } catch {
            store.remove(clientId: id)
            message = "Could not save this recording"
            return
        }
        environment.haptics.recordingSaved()
        savedMessage = "Saved on this iPhone"
        lastSavedId = id
        isTranscribing = true
        let outcome = await transcribe(audio)
        isTranscribing = false
        transcript = outcome.text
        var record = OutboxRecord.voice(clientId: id, recordedAt: environment.clock.now, durationS: duration)
        if let saved = store.records().first(where: { $0.clientId == id }) { record = saved }
        record.durationS = duration
        record.text = outcome.text
        record.transcriber = outcome.transcriber
        record.alt = outcome.alt
        do {
            try store.save(record)
        } catch {
            message = "Could not save the transcript. The recording is kept and will be sent."
        }
        if pipeline.uploader.recordingId == id { pipeline.uploader.recordingId = nil }
        await pipeline.uploader.run()
        updateDelivery()
    }

    public func discard() async {
        if pipeline.recorder.elapsed > 3 {
            confirmingDiscard = true
            isConfirmingTypeInstead = true
            return
        }
        guard await abandon() else { return }
        isClosed = true
    }

    /// Closes the screen only; the outbox record and the upload are untouched.
    public func done() {
        isClosed = true
    }

    public func requestTypeInstead() {
        guard isRecording else { return }
        confirmingDiscard = false
        isConfirmingTypeInstead = true
    }

    public func cancelTypeInstead() {
        isConfirmingTypeInstead = false
    }

    /// Ends the recording without saving it and hands over to typing.
    public func confirmTypeInstead() async {
        isConfirmingTypeInstead = false
        guard await abandon() else { return }
        isTypingInstead = !confirmingDiscard
        isClosed = true
    }

    private func abandon() async -> Bool {
        guard isRecording, let id = clientId else { return false }
        isRecording = false
        clientId = nil
        await pipeline.recorder.cancel()
        pipeline.uploader.recordingId = nil
        store.remove(clientId: id)
        savedMessage = nil
        timerText = TimerFormat.text(0)
        environment.lease.end()
        return true
    }

    public var deliveryLine: String? {
        guard savedMessage != nil else { return nil }
        if isDelivered { return "With Kit" }
        if let id = lastSavedId, pipeline.uploader.sendingId == id { return "Sending" }
        return "Will be sent when connected"
    }

    public func recordInstead() async {
        isTypingInstead = false
        await start()
    }

    private func updateDelivery() {
        guard !isDelivered, let id = lastSavedId, pipeline.uploader.confirmedIds.contains(id) else { return }
        isDelivered = true
        closeAt = environment.clock.now.addingTimeInterval(2)
    }

    private func transcribe(_ audio: Data) async -> TranscriptionOutcome {
        guard osMajor >= 26 else { return .none }
        let words = vocabulary
        let speech = try? await pipeline.speech.transcribe(audio, vocabulary: words)
        let dictation = try? await pipeline.dictation.transcribe(audio, vocabulary: words)
        return .combine(speech: speech, dictation: dictation)
    }
}
