import Foundation

/// The staged package metadata the app target reads out of its bundle. Core only ever sees the values,
/// so a test can inject a stub and the real build stamp stays outside the source tree.
public protocol BundleMetadata: Sendable {
    /// The staged package build (CFBundleVersion), or nil when the bundle carries none.
    var build: String? { get }
    /// The revision the build tooling staged into the package, or nil when it recorded none.
    var revision: String? { get }
}

/// The text of a metadata row: the staged value, or "unknown" when the injected metadata is absent.
public enum BundleMetadataText {
    public static let unknown = "unknown"

    public static func build(_ metadata: (any BundleMetadata)?) -> String {
        value(metadata?.build)
    }

    public static func revision(_ metadata: (any BundleMetadata)?) -> String {
        value(metadata?.revision)
    }

    private static func value(_ raw: String?) -> String {
        guard let raw else { return unknown }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? unknown : trimmed
    }
}
