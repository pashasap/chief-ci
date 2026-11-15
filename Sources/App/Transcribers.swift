import AVFoundation
import Foundation
import Speech
import Core

enum TranscriberKind {
    case speech, dictation
}

struct TranscriberUnavailable: Error {}

/// Both transcribers only exist on iOS 26; on older systems every call throws and the capture keeps its audio.
struct SystemTranscriber: TranscriberProtocol {
    let kind: TranscriberKind

    func transcribe(_ audio: Data, vocabulary: [String]) async throws -> String {
        guard #available(iOS 26.0, *) else { throw TranscriberUnavailable() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        try audio.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        switch kind {
        case .speech: return try await SpeechRunner.speech(url, vocabulary)
        case .dictation: return try await SpeechRunner.dictation(url, vocabulary)
        }
    }

    static var availability: TranscriberAvailability {
        guard #available(iOS 26.0, *) else { return TranscriberAvailability(speech: false, dictation: false) }
        return TranscriberAvailability(speech: SpeechTranscriber.isAvailable, dictation: true)
    }
}

@available(iOS 26.0, *)
enum SpeechRunner {
    private static let locale = Locale(identifier: "en_US")

    static func speech(_ url: URL, _ vocabulary: [String]) async throws -> String {
        let module = SpeechTranscriber(
            locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
        try await install(module)
        async let text = collect(module.results)
        try await analyze([module], url, vocabulary)
        return try await text
    }

    static func dictation(_ url: URL, _ vocabulary: [String]) async throws -> String {
        let module = DictationTranscriber(locale: locale, preset: .shortDictation)
        try await install(module)
        async let text = collect(module.results)
        try await analyze([module], url, vocabulary)
        return try await text
    }

    private static func install(_ module: some SpeechModule) async throws {
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
    }

    private static func analyze(_ modules: [any SpeechModule], _ url: URL, _ vocabulary: [String]) async throws {
        let analyzer = SpeechAnalyzer(modules: modules)
        if !vocabulary.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = vocabulary
            try await analyzer.setContext(context)
        }
        let file = try AVAudioFile(forReading: url)
        if let last = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            await analyzer.cancelAndFinishNow()
        }
    }

    private static func collect<S: AsyncSequence>(_ results: S) async throws -> String
    where S.Element: SpeechResultText {
        var text = ""
        for try await result in results { text += String(result.resultText.characters) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@available(iOS 26.0, *)
protocol SpeechResultText {
    var resultText: AttributedString { get }
}

@available(iOS 26.0, *)
extension SpeechTranscriber.Result: SpeechResultText {
    var resultText: AttributedString { text }
}

@available(iOS 26.0, *)
extension DictationTranscriber.Result: SpeechResultText {
    var resultText: AttributedString { text }
}
