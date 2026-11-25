import Foundation

struct CaptureDraft: Codable, Equatable {
    static let fileName = "typed-capture.draft"
    static let currentVersion = 1

    var version = Self.currentVersion
    let id: String
    let text: String

    static func read(from files: any FileStore) throws -> Self? {
        guard let data = try files.read(fileName) else { return nil }
        let draft = try JSONDecoder().decode(Self.self, from: data)
        guard draft.version == currentVersion else { throw DraftError.unsupportedVersion }
        guard UUID(uuidString: draft.id) != nil else { throw DraftError.invalidID }
        return draft
    }

    private enum DraftError: Error { case unsupportedVersion, invalidID }
}
