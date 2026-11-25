import Foundation

public enum VoiceQualityTier: Int, Comparable, Equatable, Sendable {
    case standard = 1
    case enhanced = 2
    case premium = 3

    public static func < (lhs: VoiceQualityTier, rhs: VoiceQualityTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .standard: return "Default"
        case .enhanced: return "Enhanced"
        case .premium: return "Premium"
        }
    }
}

public struct VoiceCandidate: Equatable, Sendable {
    public let identifier: String
    public let name: String
    public let language: String
    public let tier: VoiceQualityTier

    public init(identifier: String, name: String, language: String, tier: VoiceQualityTier) {
        self.identifier = identifier
        self.name = name
        self.language = language
        self.tier = tier
    }

    public var baseName: String {
        let suffixes = [" (Premium)", " (Enhanced)", " (Compact)", " (Default)"]
        for suffix in suffixes where name.localizedCaseInsensitiveCompare(
            String(name.dropLast(suffix.count)) + suffix) == .orderedSame && name.count > suffix.count {
            return String(name.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var displayName: String {
        "\(baseName) (\(tier.label) · \(language))"
    }
}

public enum VoiceSelector {
    private static let preferredOrder = ["zoe", "samantha", "ava", "nicky"]

    public static func selectBest(from candidates: [VoiceCandidate]) -> VoiceCandidate? {
        let usVoices = candidates.filter { normalizeLanguage($0.language) == "en-us" }
        let pool = usVoices.isEmpty
            ? candidates.filter { normalizeLanguage($0.language).hasPrefix("en") }
            : usVoices
        return pool.max(by: { isBetter($1, than: $0) })
    }

    private static func normalizeLanguage(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    private static func preferredRank(for candidate: VoiceCandidate) -> Int {
        let lower = candidate.baseName.lowercased()
        for (offset, target) in preferredOrder.enumerated() {
            if lower == target || lower.hasPrefix(target + " ") {
                return preferredOrder.count - offset
            }
        }
        return 0
    }

    private static func isBetter(_ lhs: VoiceCandidate, than rhs: VoiceCandidate) -> Bool {
        if lhs.tier != rhs.tier { return lhs.tier > rhs.tier }
        let lhsRank = preferredRank(for: lhs)
        let rhsRank = preferredRank(for: rhs)
        if lhsRank != rhsRank { return lhsRank > rhsRank }
        if lhs.baseName != rhs.baseName { return lhs.baseName < rhs.baseName }
        return lhs.identifier < rhs.identifier
    }
}

public struct SettingsEntry: Codable, Equatable, Sendable {
    public var label: String
    public var value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public enum SettingsAction: Equatable, Sendable { case pasteLink, checkServer, unpair, copyDiagnostics }

public struct SettingsControl: Equatable, Sendable {
    public var label: String
    public var action: SettingsAction
    public var role: ControlRole
    public var isEnabled: Bool
}

public struct SettingsHostSummary: Equatable, Sendable {
    public let isPaired: Bool
    public let statusText: String
    public let serverHost: String
    public let pendingQueueCount: Int
    public let lastSnapshotText: String
    public let framingSignalCount: Int
}

public struct SettingsCaptureSummary: Equatable, Sendable {
    public let radialSummary: String
    public let speechLocale: String
    public let speechAvailable: Bool
    public let dictationAvailable: Bool
    public let defaultBriefTime: String
    public let briefingVoiceLabel: String
    public let briefingVoiceHint: String?
    public let locationPermissionState: LocationPermissionState
    public let weatherStatusLabel: String
    public let weatherHint: String?
}

public struct DiagnosticsExportPayload: Codable, Equatable, Sendable {
    public let appVersion: String
    public let packageBuild: String
    public let packageRevision: String
    public let snapshotAPI: String
    public let pendingQueueCount: Int
    public let framingSignalCount: Int
    public let framingSummary: String
    public let diagnostics: [SettingsEntry]
}

/// Everything the settings screen shows, as plain values. The view renders this and nothing else.
public struct SettingsScreen: Equatable, Sendable {
    public let eyebrow = "Preferences"
    public let title = "Settings"
    public let hostSectionTitle = "Host & Sync"
    public let focusSectionTitle = "AI Focus Screening"
    public let captureSectionTitle = "Capture, Speech & Reminders"
    public let statusTitle = "Status"
    public let pairTitle = "Pair"
    public let pairingLinkLabel = "Pairing link"
    public let pairLinkHint = "Pair with this link"
    public let unpairTitle = "Unpair this iPhone?"
    public let unpairLabel = "Unpair"
    public let cancelLabel = "Cancel"
    public let unpairExplanation = "Captures waiting on this iPhone are kept."
    public let greetingNameLabel = "Your name"
    public let pairAlignment: ControlAlignment = .leading
    public let pasteLinkAlignment: ControlAlignment = .leading
    public let entries: [SettingsEntry]
    public let greetingName: String
    public let explanation: String?
    public let controls: [SettingsControl]
    public let reminders: RemindersSection
    public let checkResult: String?
    public let diagnostics: DiagnosticsSection
    public let hostSummary: SettingsHostSummary
    public let captureSummary: SettingsCaptureSummary
    public let versionFooter: String

    private let exportContext: DiagnosticsExportContext

    @MainActor
    public init(
        model: SettingsModel,
        framingSignalCount: Int = 0,
        selectedVoice: VoiceCandidate? = nil,
        weather: WeatherLocationModel? = nil
    ) {
        let paired = model.isPaired
        let allEntries = model.entries
        let diag = DiagnosticsSection(
            title: "Diagnostics", rows: model.legacyDiagnosticsRows,
            health: model.factDiagnosticsRows,
            copyControl: SettingsControl(
                label: "Copy diagnostics", action: .copyDiagnostics, role: .normal, isEnabled: true))
        checkResult = model.checkResult
        diagnostics = diag
        entries = allEntries
        greetingName = model.greetingName
        reminders = RemindersSection(reminders: model.reminders, timeZone: model.timeZone)
        explanation = paired ? nil : "Captures are waiting on this iPhone until you pair"
        controls = [
            SettingsControl(label: "Paste link", action: .pasteLink, role: .normal, isEnabled: true),
            SettingsControl(label: "Check server", action: .checkServer, role: .normal, isEnabled: paired),
            SettingsControl(label: "Unpair", action: .unpair, role: .destructive, isEnabled: paired),
        ]
        hostSummary = Self.makeHostSummary(
            paired: paired, entries: allEntries, framingSignalCount: framingSignalCount)
        captureSummary = Self.makeCaptureSummary(
            model: model, selectedVoice: selectedVoice, weather: weather)
        let build = BundleMetadataText.build(model.services.bundleMetadata)
        let revision = BundleMetadataText.revision(model.services.bundleMetadata)
        versionFooter = "Kit \(model.appVersion) · Build \(build) · Commit \(revision)"
        let api = SnapshotCache(files: model.services.files).load().map { String($0.snapshot.api) } ?? "none"
        exportContext = DiagnosticsExportContext(
            appVersion: model.appVersion,
            packageBuild: build,
            packageRevision: revision,
            snapshotAPI: api,
            pendingQueueCount: hostSummary.pendingQueueCount,
            framingSignalCount: framingSignalCount,
            diagnostics: diag.rows + diag.health
        )
    }

    public func diagnosticsExportData(framingSummary: String) -> Data? {
        let payload = DiagnosticsExportPayload(
            appVersion: exportContext.appVersion,
            packageBuild: exportContext.packageBuild,
            packageRevision: exportContext.packageRevision,
            snapshotAPI: exportContext.snapshotAPI,
            pendingQueueCount: exportContext.pendingQueueCount,
            framingSignalCount: exportContext.framingSignalCount,
            framingSummary: framingSummary,
            diagnostics: exportContext.diagnostics
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(payload)
    }

    @MainActor
    private static func makeCaptureSummary(
        model: SettingsModel, selectedVoice: VoiceCandidate?, weather: WeatherLocationModel?
    ) -> SettingsCaptureSummary {
        let voiceLabel = selectedVoice?.displayName ?? "System Default (en-US)"
        let needsUpgrade = selectedVoice?.tier == .standard
        let voiceHint = needsUpgrade
            ? "Download Zoe (Premium) in iOS Settings › Accessibility › Spoken Content › Voices."
            : nil
        return SettingsCaptureSummary(
            radialSummary: "Type · Attach · Voice",
            speechLocale: "en-US",
            speechAvailable: model.services.transcribers.speech,
            dictationAvailable: model.services.transcribers.dictation,
            defaultBriefTime: "07:40",
            briefingVoiceLabel: voiceLabel,
            briefingVoiceHint: voiceHint,
            locationPermissionState: weather?.permissionState ?? .notDetermined,
            weatherStatusLabel: weather?.settingsStatusLabel ?? "Not Enabled",
            weatherHint: weather?.statusCaption
        )
    }

    private static func makeHostSummary(
        paired: Bool, entries: [SettingsEntry], framingSignalCount: Int
    ) -> SettingsHostSummary {
        let address = entries.first { $0.label == "Server address" }?.value ?? "No server address"
        let host = URLComponents(string: address)?.host ?? address
        let queueRaw = entries.first { $0.label == "Waiting in outbox" }?.value ?? "0"
        let snapshotText = entries.first { $0.label == "Last snapshot" }?.value ?? "No snapshot yet"
        return SettingsHostSummary(
            isPaired: paired,
            statusText: paired ? "Paired" : "Not paired",
            serverHost: host,
            pendingQueueCount: Int(queueRaw) ?? 0,
            lastSnapshotText: snapshotText,
            framingSignalCount: framingSignalCount
        )
    }
}

private struct DiagnosticsExportContext: Equatable, Sendable {
    let appVersion: String
    let packageBuild: String
    let packageRevision: String
    let snapshotAPI: String
    let pendingQueueCount: Int
    let framingSignalCount: Int
    let diagnostics: [SettingsEntry]
}
