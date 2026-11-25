import Foundation
import Observation

/// Which task tiles are showing their whole text. In memory only, one per screen model.
@MainActor @Observable
public final class TaskExpansionModel {
    public private(set) var expandedIDs: Set<String> = []

    public init() {}

    public func isExpanded(_ id: String) -> Bool {
        expandedIDs.contains(id)
    }

    public func toggle(_ id: String) {
        if expandedIDs.contains(id) {
            expandedIDs.remove(id)
        } else {
            expandedIDs.insert(id)
        }
    }

    public func collapseAll() {
        expandedIDs.removeAll()
    }
}

/// Copies tiles with `isExpanded` set from an id set; the text stays whole either way.
public enum TileExpansion {
    public static func tiles(_ tiles: [UniversalTaskTile], expandedIDs: Set<String>) -> [UniversalTaskTile] {
        tiles.map { $0.withExpansion(expandedIDs.contains($0.id)) }
    }
}
