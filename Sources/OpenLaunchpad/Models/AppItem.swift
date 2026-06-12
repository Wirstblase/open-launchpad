import AppKit

// MARK: - App Item Model

/// Represents a single installed application discovered on the system.
struct AppItem: Identifiable, Hashable, Codable {
    /// Unique identifier — uses bundle ID if available, otherwise the app path.
    let id: String
    /// Human-readable display name from Info.plist or the .app filename.
    let name: String
    /// Absolute path to the .app bundle (e.g., /Applications/Safari.app).
    let path: String
    /// The CFBundleIdentifier, if present in Info.plist.
    let bundleID: String?
    /// True if this app resides in /System/Applications.
    let isSystemApp: Bool

    // MARK: Non-Codable (resolved at runtime)

    /// The app icon, resolved asynchronously and cached.
    var icon: NSImage?

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case id, name, path, bundleID, isSystemApp
    }

    // MARK: Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AppItem, rhs: AppItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Folder Model

/// A user-created folder grouping multiple apps together on the Launchpad grid.
struct AppFolder: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    /// Ordered list of app IDs contained in this folder.
    var appIDs: [String]

    init(id: UUID = UUID(), name: String = "New Folder", appIDs: [String] = []) {
        self.id = id
        self.name = name
        self.appIDs = appIDs
    }
}

// MARK: - Layout State

/// The full persisted layout: ordered items (apps + folders) and folder definitions.
struct LayoutState: Codable {
    /// Ordered list of item IDs — apps appear by their bundleID/path,
    /// folders appear as "folder-{UUID}".
    var orderedItemIDs: [String]
    /// Folder definitions keyed by folder ID.
    var folders: [UUID: AppFolder]
    /// App IDs that the user has chosen to hide from the grid.
    var hiddenAppIDs: Set<String>

    static let `default` = LayoutState(
        orderedItemIDs: [],
        folders: [:],
        hiddenAppIDs: []
    )
}
