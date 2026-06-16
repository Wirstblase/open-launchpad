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
                    // IconResolver.generateFallbackIcon and .resizeImage both call
                    // NSImage.lockFocus() which MUST run on the main thread.
                    let icon = await MainActor.run {
                        IconResolver.resolveIcon(for: app, size: self.iconSize)
                    }
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

    // MARK: - Folder Preview Cache

    /// Returns a cached folder preview icon, rendering it if not already cached.
    /// The preview is a 3×3 mini-grid of the first 9 app icons in the folder.
    /// - Parameters:
    ///   - folderID: The folder's UUID for cache lookup.
    ///   - appIDs: Ordered list of app IDs in the folder (used for invalidation).
    ///   - size: The desired point size for the preview icon.
    func folderPreview(folderID: String, appIDs: [String], size: CGFloat) async -> NSImage? {
        let cacheKey = "folder-\(folderID)"

        // Check if cached
        if let cached = storage[cacheKey] {
            return cached
        }

        // Render on main thread (NSBitmapImageRep + NSGraphicsContext require it)
        guard let rendered = await MainActor.run(body: {
            renderFolderPreview(appIDs: appIDs, size: size)
        }) else { return nil }

        storage[cacheKey] = rendered
        return rendered
    }

    /// Invalidates a cached folder preview (call when folder contents change).
    func invalidateFolder(folderID: String) {
        storage.removeValue(forKey: "folder-\(folderID)")
    }

    // MARK: - Folder Preview Rendering

    /// Renders a 3×3 mini-grid preview for folder icons.
    /// Runs CPU-side bitmap drawing — cache aggressively.
    private nonisolated func renderFolderPreview(appIDs: [String], size: CGFloat) -> NSImage? {
        let previewSize = size
        let scale: CGFloat = 2.0
        let pixelW = Int(previewSize * scale)
        let pixelH = Int(previewSize * scale)
        let mini = previewSize * 0.24
        let gap = previewSize * 0.05
        let pad = (previewSize - 3 * mini - 2 * gap) / 2

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelW,
            pixelsHigh: pixelH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        rep.size = NSSize(width: previewSize, height: previewSize)

        let nsContext = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext

        // Background rounded rect
        let bgPath = NSBezierPath(
            roundedRect: NSRect(x: 0, y: 0, width: previewSize, height: previewSize),
            xRadius: previewSize * 0.225,
            yRadius: previewSize * 0.225
        )
        NSColor.white.withAlphaComponent(0.15).setFill()
        bgPath.fill()

        let iconCount = min(appIDs.count, 9)
        for i in 0..<iconCount {
            let col = CGFloat(i % 3)
            let row = CGFloat(i / 3)
            let x = pad + col * (mini + gap)
            let y = pad + (2 - row) * (mini + gap)
            let rect = NSRect(x: x, y: y, width: mini, height: mini)

            // Use NSWorkspace icon synchronously — this is why we cache aggressively
            // We can't use the actor cache here because we're nonisolated
            let ws = NSWorkspace.shared
            // Find the app path from the app ID (bundle ID or path)
            if let appPath = resolveAppPath(for: appIDs[i]) {
                let icon = ws.icon(forFile: appPath)
                icon.size = NSSize(width: mini * scale, height: mini * scale)
                icon.draw(in: rect,
                          from: NSRect(x: 0, y: 0, width: icon.size.width, height: icon.size.height),
                          operation: .sourceOver, fraction: 1.0)
            } else {
                let hue = CGFloat(abs(appIDs[i].hashValue) % 256) / 256.0
                NSColor(hue: hue, saturation: 0.5, brightness: 0.7, alpha: 0.6).setFill()
                NSBezierPath(roundedRect: rect, xRadius: mini * 0.2, yRadius: mini * 0.2).fill()
            }
        }

        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: previewSize, height: previewSize))
        image.addRepresentation(rep)
        return image
    }

    /// Resolves an app ID to its filesystem path for icon loading.
    /// Tries bundle ID → path lookup via NSWorkspace first, then treats the ID as a path.
    private nonisolated func resolveAppPath(for appID: String) -> String? {
        // Try as bundle ID
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appID) {
            return url.path
        }
        // Try as filesystem path
        if FileManager.default.fileExists(atPath: appID), appID.hasSuffix(".app") {
            return appID
        }
        return nil
    }
}
