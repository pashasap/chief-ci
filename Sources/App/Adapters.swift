import AVFoundation
import Foundation
import UIKit
import Core

struct DirectoryFileStore: FileStore {
    let folder: URL

    init(folderName: String) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = base.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    init(folder: URL) {
        self.folder = folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func read(_ name: String) throws -> Data? {
        let url = folder.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    func write(_ data: Data, name: String) throws {
        try data.write(to: folder.appendingPathComponent(name), options: .atomic)
    }

    func remove(_ name: String) throws {
        let url = folder.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    func list() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }
}

struct SystemClock: Core.Clock {
    var now: Date { Date() }
}

struct PasteboardClipboard: ClipboardAdapter {
    func copy(_ text: String) {
        _Concurrency.Task { @MainActor in UIPasteboard.general.string = text }
    }
}

struct RandomIDs: UUIDSource {
    func next() -> UUID { UUID() }
}

struct SystemHaptics: Haptics {
    func recordingStarted() { fire(.medium) }
    func recordingSaved() { fire(.light) }

    private func fire(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        _Concurrency.Task { @MainActor in
            UIImpactFeedbackGenerator(style: style).impactOccurred()
        }
    }
}

final class SystemLease: BackgroundLease, @unchecked Sendable {
    private let lock = NSLock()
    private var identifier = UIBackgroundTaskIdentifier.invalid

    func begin() {
        _Concurrency.Task { @MainActor in
            let previous = self.take()
            if previous != .invalid { UIApplication.shared.endBackgroundTask(previous) }
            let id = UIApplication.shared.beginBackgroundTask(withName: "chief.recording")
            self.store(id)
        }
    }

    func end() {
        let id = take()
        guard id != .invalid else { return }
        _Concurrency.Task { @MainActor in UIApplication.shared.endBackgroundTask(id) }
    }

    private func store(_ id: UIBackgroundTaskIdentifier) {
        lock.lock()
        defer { lock.unlock() }
        identifier = id
    }

    private func take() -> UIBackgroundTaskIdentifier {
        lock.lock()
        defer { lock.unlock() }
        let id = identifier
        identifier = .invalid
        return id
    }
}

final class AudioRecorderAdapter: RecorderProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?

    var elapsed: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return recorder?.currentTime ?? 0
    }

    /// Average input power mapped from -60...0 dB onto 0...1.
    var level: Double {
        lock.lock()
        defer { lock.unlock() }
        guard let recorder else { return 0 }
        recorder.updateMeters()
        let decibels = Double(recorder.averagePower(forChannel: 0))
        return min(1, max(0, (decibels + 60) / 60))
    }

    func start(clientId: String) async throws {
        guard await AVAudioApplication.requestRecordPermission() else { throw RecorderError.permissionDenied }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(clientId + ".m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let made = try AVAudioRecorder(url: url, settings: settings)
        made.isMeteringEnabled = true
        guard made.record() else { throw RecorderError.permissionDenied }
        attach(made, url)
    }

    private func attach(_ made: AVAudioRecorder, _ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        recorder = made
        fileURL = url
    }

    func stop() async throws -> Data {
        let (active, url) = detach()
        active?.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard let url else { return Data() }
        defer { try? FileManager.default.removeItem(at: url) }
        return try Data(contentsOf: url)
    }

    func cancel() async {
        let (active, url) = detach()
        active?.stop()
        if let url { try? FileManager.default.removeItem(at: url) }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func detach() -> (AVAudioRecorder?, URL?) {
        lock.lock()
        defer { lock.unlock() }
        let result = (recorder, fileURL)
        recorder = nil
        fileURL = nil
        return result
    }
}
