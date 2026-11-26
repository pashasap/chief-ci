/// Maps an audit stop id to the root accessibility identifier its screen carries.
public enum AuditRootID {
    public static let prefix = "kit.audit."

    /// `kit.audit.<id>` for a known stop, nil for anything else.
    public static func identifier(for stopID: String) -> String? {
        guard AuditStops.all.contains(where: { $0.id == stopID }) else { return nil }
        return prefix + stopID
    }

    /// The owner name the Tasks tab reports for the current segment; idea-control and picks stops own it.
    public static func tasksOwner(segment: Int, stopID: String?) -> String {
        if let stopID, let owner = AuditRoute.rootOwner(for: stopID),
            ["idea-controls", "tasks-today-picks", "tasks-later-candidate"].contains(owner) {
            return owner
        }
        let owners = ["tasks-today", "tasks-later", "tasks-waiting", "tasks-ideas"]
        return owners[min(max(segment, 0), owners.count - 1)]
    }
}

/// The step that runs after the audit fixture has prepared its capture state.
public enum AuditWiring {
    /// Opens the stop's destination tab without touching the presented capture state and returns its root id.
    @MainActor
    public static func exposedRoot(stopID: String, coordinator: AppCoordinator) -> String? {
        guard let root = AuditRootID.identifier(for: stopID),
              let destination = AuditRoute.destination(for: stopID) else { return nil }
        coordinator.open(route: destination.showsSearch ? .search : .tab(destination.tab))
        return root
    }
}
