import Foundation
import Observation

@MainActor
@Observable
public final class TypedCaptureModel {
    public private(set) var message: String?
    public private(set) var isClosed = false
    public var text = ""
    @ObservationIgnored public var afterSave: (@MainActor () -> Void)?

    @ObservationIgnored private let store: OutboxStore
    @ObservationIgnored private let clock: any Clock
    @ObservationIgnored private let ids: any UUIDSource

    public init(store: OutboxStore, clock: any Clock, ids: any UUIDSource) {
        self.store = store
        self.clock = clock
        self.ids = ids
    }

    /// Stores nothing and closes the screen.
    public func cancel() {
        message = nil
        isClosed = true
    }

    /// Reopens the screen for a new note.
    public func reopen() {
        message = nil
        isClosed = false
    }

    public func save(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            message = "Type something first"
            return
        }
        let record = OutboxRecord.typed(
            clientId: ids.next().uuidString.lowercased(), recordedAt: clock.now, text: trimmed)
        do {
            try store.save(record)
            message = nil
            isClosed = true
            self.text = ""
            afterSave?()
        } catch {
            message = "Could not save this note"
        }
    }
}
