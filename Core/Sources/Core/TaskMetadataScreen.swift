import Foundation

/// The More sheet's content: the task handle, its revision and capture, and the codes its note carries.
/// Identifiers are confined to this sheet, never shown on the tile.
public struct TaskMetadataScreen: Equatable, Sendable {
    public let title = "Task details"
    public let handleLabel = "Handle"
    public let revisionLabel = "Revision"
    public let captureLabel = "Capture"
    public let codesLabel = "Codes"
    public let handle: String
    public let revision: String?
    public let capture: String?
    /// The metadata codes of the task's note, without duplicates; an empty list when it carries none.
    public let associatedCodes: [String]
    public let done = InboxControl(label: "Done", role: .normal, isEnabled: true, state: .idle,
        action: .closeTaskMore, accessibilityLabel: "Done")

    init(task: TaskItem) {
        handle = task.handle
        revision = task.rev
        capture = task.capture
        associatedCodes = TaskTileText.codes(task.note)
    }
}
