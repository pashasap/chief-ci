import Core
import Foundation

/// Reads the staged package metadata the build tooling put inside the app bundle. Nothing here is a
/// hardcoded source stamp: when the bundle carries no value, the row stays "unknown" in Core.
struct BundlePackageMetadata: BundleMetadata {
    /// CFBundleVersion of the staged package.
    var build: String? { value(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) }

    /// The revision the build tooling staged next to the app: a PackageMetadata.json resource first,
    /// then the matching Info.plist entry.
    var revision: String? {
        stagedRevision() ?? value(Bundle.main.object(forInfoDictionaryKey: "PackageRevision") as? String)
    }

    private func stagedRevision() -> String? {
        guard let url = Bundle.main.url(forResource: "PackageMetadata", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return value(object["revision"] as? String)
    }

    private func value(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
