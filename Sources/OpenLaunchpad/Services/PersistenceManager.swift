import Foundation

// MARK: - Persistence Manager

/// Manages persistence of the Launchpad layout state to/from a JSON file
/// in the user's Application Support directory.
enum PersistenceManager {

    // MARK: - File Location

    private static var storageURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let folder = appSupport.appendingPathComponent("OpenLaunchpad")
        try? FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        return folder.appendingPathComponent("layout.json")
    }

    // MARK: - Public API

    /// Loads the saved layout state, or returns a default empty state.
    static func load() -> LayoutState {
        guard let data = try? Data(contentsOf: storageURL) else {
            return .default
        }
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(LayoutState.self, from: data)
        } catch {
            print("[OpenLaunchpad] Failed to decode layout state: \(error.localizedDescription)")
            // If the file is corrupted, back it up and start fresh
            backupCorruptFile()
            return .default
        }
    }

    /// Saves the layout state to disk.
    static func save(_ state: LayoutState) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("[OpenLaunchpad] Failed to save layout state: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    /// Moves a corrupted layout file to a backup location so the app can start fresh.
    private static func backupCorruptFile() {
        let timestamp = Int(Date().timeIntervalSince1970)
        let backupURL = storageURL
            .deletingPathExtension()
            .appendingPathExtension("corrupt-\(timestamp).json")
        try? FileManager.default.moveItem(at: storageURL, to: backupURL)
        print("[OpenLaunchpad] Backed up corrupt layout file to \(backupURL.lastPathComponent)")
    }
}
