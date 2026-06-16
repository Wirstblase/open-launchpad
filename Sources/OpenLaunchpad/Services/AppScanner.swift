import AppKit
import Foundation

// MARK: - App Scanner

/// Discovers installed .app bundles from standard macOS application directories,
/// filters out system helpers, and resolves layout state from saved preferences.
enum AppScanner {

    // MARK: - Scan Directories

    /// Directories scanned for .app bundles, in order of priority.
    /// Later directories override earlier ones on bundle ID collision.
    static let scanDirectories: [(path: String, isSystem: Bool)] = [
        ("/Applications", false),
        ("/Applications/Utilities", false),
        ("/System/Applications", true),
        ("/System/Applications/Utilities", true),
        (NSHomeDirectory() + "/Applications", false),
    ]

    /// Bundle IDs known to be background/system helpers that should not appear in the grid.
    private static let hiddenBundleIDs: Set<String> = [
        "com.apple.ReportCrash",
        "com.apple.SoftwareUpdateNotification",
        "com.apple.mrt.ui",
        "com.apple.Spotlight",
        "com.apple.java.utilities.JavaAppLauncher",
        "com.apple.JarLauncher",
    ]

    // MARK: - Public API

    /// Scans all configured directories and returns a deduplicated, filtered list of `AppItem`s.
    static func scanForApps() -> [AppItem] {
        var appsByID: [String: AppItem] = [:]

        for (directory, isSystem) in scanDirectories {
            guard let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: directory),
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension == "app" else { continue }

                // Only process .app bundles at depth 1 or 2 (not deep inside packages)
                let relativeDepth = url.pathComponents.count - URL(fileURLWithPath: directory).pathComponents.count
                guard relativeDepth <= 2 else {
                    if relativeDepth > 2 { enumerator.skipDescendants() }
                    continue
                }

                guard let item = appItem(from: url, isSystem: isSystem) else { continue }

                // Skip known background helpers
                if let bundleID = item.bundleID, hiddenBundleIDs.contains(bundleID) {
                    continue
                }

                // De-duplicate: first occurrence wins (higher-priority directories scanned first)
                if appsByID[item.id] == nil {
                    appsByID[item.id] = item
                }
            }
        }

        return Array(appsByID.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Merges scanned apps with saved layout state to produce the ordered grid.
    /// - Newly installed apps are appended at the end.
    /// - Uninstalled apps (no longer on disk) are removed.
    /// - Folders with missing apps have those apps removed; empty folders are dissolved.
    static func resolveLayout(
        apps: [AppItem],
        layout: LayoutState
    ) -> (gridItems: [LaunchpadItem], updatedLayout: LayoutState) {
        let appsByID = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var folders = layout.folders
        var hiddenIDs = layout.hiddenAppIDs
        var orderedIDs = layout.orderedItemIDs
        let knownIDs = Set(appsByID.keys)
        // Purge hidden apps that no longer exist
        hiddenIDs = hiddenIDs.intersection(knownIDs)

        // Purge folder references to uninstalled apps
        for folderID in folders.keys {
            folders[folderID]?.appIDs.removeAll { !knownIDs.contains($0) }
        }
        // Dissolve empty or single-app folders
        let foldersToDissolve = folders.filter { $0.value.appIDs.count <= 1 }
        for (folderID, folder) in foldersToDissolve {
            folders.removeValue(forKey: folderID)
            if let idx = orderedIDs.firstIndex(of: "folder-\(folderID.uuidString)") {
                orderedIDs.remove(at: idx)
                // Re-insert the orphaned app at the folder's position
                if let orphanID = folder.appIDs.first {
                    orderedIDs.insert(orphanID, at: idx)
                }
            }
        }

        // Remove ordered IDs that no longer exist on disk
        orderedIDs.removeAll { id in
            if id.hasPrefix("folder-") { return !folders.keys.contains(where: { "folder-\($0.uuidString)" == id }) }
            return !knownIDs.contains(id)
        }

        // Collect all app IDs that live inside folders so we don't append
        // them as standalone items when scanning for newly discovered apps.
        var appsInFolders = Set<String>()
        for (_, folder) in folders {
            appsInFolders.formUnion(folder.appIDs)
        }

        // Append newly discovered apps that aren't in the saved order,
        // aren't hidden, and aren't already contained inside a folder.
        let existingOrderedSet = Set(orderedIDs)
        for app in apps {
            if !existingOrderedSet.contains(app.id)
                && !hiddenIDs.contains(app.id)
                && !appsInFolders.contains(app.id)
            {
                orderedIDs.append(app.id)
            }
        }

        // Build grid items from ordered IDs
        var gridItems: [LaunchpadItem] = []
        for id in orderedIDs {
            if id.hasPrefix("folder-"),
               let folderID = UUID(uuidString: String(id.dropFirst("folder-".count))),
               let folder = folders[folderID]
            {
                let folderApps = folder.appIDs.compactMap { appsByID[$0] }
                if !folderApps.isEmpty {
                    gridItems.append(.folder(folder, folderApps))
                }
            } else if let app = appsByID[id], !hiddenIDs.contains(id) {
                gridItems.append(.app(app))
            }
        }

        let updatedLayout = LayoutState(
            orderedItemIDs: orderedIDs,
            folders: folders,
            hiddenAppIDs: hiddenIDs
        )

        return (gridItems, updatedLayout)
    }

    /// Launches an app and records usage.
    static func launch(app: AppItem) {
        let url = URL(fileURLWithPath: app.path)
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error = error {
                print("[OpenLaunchpad] Failed to launch \(app.name): \(error.localizedDescription)")
            }
        }

        // Record launch for future frecency ranking
        recordLaunch(appID: app.id)
    }

    // MARK: - Launch Tracking

    private static func recordLaunch(appID: String) {
        var counts = launchCounts()
        counts[appID, default: 0] += 1
        UserDefaults.standard.set(counts, forKey: "OpenLaunchpadLaunchCounts")
    }

    static func launchCounts() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: "OpenLaunchpadLaunchCounts") as? [String: Int] ?? [:]
    }

    // MARK: - Private Helpers

    /// Extracts an `AppItem` from a .app bundle URL.
    private static func appItem(from url: URL, isSystem: Bool) -> AppItem? {
        let bundle = Bundle(url: url)
        let infoDict = bundle?.infoDictionary

        // Determine the identifier: prefer bundle ID, fall back to path
        let bundleID = infoDict?["CFBundleIdentifier"] as? String
        let id = bundleID ?? url.path

        // Determine display name
        let displayName: String
        if let name = infoDict?["CFBundleDisplayName"] as? String, !name.isEmpty {
            displayName = name
        } else if let name = infoDict?["CFBundleName"] as? String, !name.isEmpty {
            displayName = name
        } else {
            displayName = url.deletingPathExtension().lastPathComponent
        }

        // Skip apps with empty or whitespace-only names
        guard !displayName.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

        return AppItem(
            id: id,
            name: displayName,
            path: url.path,
            bundleID: bundleID,
            isSystemApp: isSystem,
            icon: nil // Resolved later by IconResolver + IconCache
        )
    }
}
