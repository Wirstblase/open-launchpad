import AppKit
import Foundation

// MARK: - Icon Cache

/// An actor-based, thread-safe cache for resolved app icons.
/// Icons are pre-rendered at a configurable size (default 72pt @2x).
actor IconCache {

    // MARK: - Singleton

    static let shared = IconCache()

    // MARK: - Properties

    private var storage: [String: NSImage] = [:]
    private let iconSize: CGFloat

    // MARK: - Init

    init(iconSize: CGFloat = IconResolver.defaultIconSize) {
        self.iconSize = iconSize
    }

    // MARK: - Public API

    /// Returns the cached icon for an app, resolving it if not already cached.
    func icon(for app: AppItem) -> NSImage {
        if let cached = storage[app.id] {
            return cached
        }
        let resolved = IconResolver.resolveIcon(for: app, size: iconSize)
        storage[app.id] = resolved
        return resolved
    }

    /// Pre-renders icons for a batch of apps (call at startup).
    /// - Parameter apps: The apps to pre-cache icons for.
    func prewarmBatch(_ apps: [AppItem]) async {
        await withTaskGroup(of: (String, NSImage).self) { group in
            for app in apps {
                group.addTask {
                    let icon = IconResolver.resolveIcon(for: app, size: self.iconSize)
                    return (app.id, icon)
                }
            }
            for await (id, icon) in group {
                storage[id] = icon
            }
        }
        print("[OpenLaunchpad] IconCache prewarmed \(storage.count) icons")
    }

    /// Removes all cached icons.
    func clear() {
        storage.removeAll()
    }

    /// Removes a specific app's cached icon.
    func invalidate(appID: String) {
        storage.removeValue(forKey: appID)
    }
}
