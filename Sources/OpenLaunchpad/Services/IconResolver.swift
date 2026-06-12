import AppKit
import Foundation

// MARK: - Icon Resolver

/// Resolves app icons using a three-tier fallback strategy:
/// 1. `NSWorkspace.shared.icon(forFile:)` — the system icon
/// 2. Bundle metadata (`CFBundleIconFile` / `CFBundleIconName`) — custom icon file
/// 3. Generated initials-based fallback — guaranteed to produce something
enum IconResolver {

    /// The default icon size for the grid (points, 2x for Retina).
    static let defaultIconSize: CGFloat = 72

    /// Resolves the best available icon for an app at the given size.
    /// - Parameters:
    ///   - app: The app to resolve an icon for.
    ///   - size: The desired point size (will be scaled for Retina).
    /// - Returns: An `NSImage` at the requested size, or a generated fallback.
    static func resolveIcon(for app: AppItem, size: CGFloat = defaultIconSize) -> NSImage {
        // Tier 1: NSWorkspace icon
        let workspaceIcon = NSWorkspace.shared.icon(forFile: app.path)
        if !isGenericIcon(workspaceIcon) {
            return resizeImage(workspaceIcon, to: size)
        }

        // Tier 2: Bundle metadata
        if let bundle = Bundle(path: app.path),
           let iconName = bundleIconName(from: bundle) {
            if let bundledIcon = iconFromBundle(bundle, iconName: iconName, size: size) {
                return bundledIcon
            }
        }

        // Tier 3: Generated fallback
        return generateFallbackIcon(for: app.name, size: size)
    }

    // MARK: - Private Helpers

    /// Checks if an icon is the generic/default application icon.
    private static func isGenericIcon(_ icon: NSImage) -> Bool {
        // The generic app icon is typically 32x32 or small with few representations.
        // We check if it has low resolution and few representations.
        let reps = icon.representations
        if reps.isEmpty { return true }
        // If all representations are small (<=32pt), it's likely generic
        let sizes = reps.compactMap { ($0 as? NSBitmapImageRep)?.size.width }
        if !sizes.isEmpty && sizes.allSatisfy({ $0 <= 32 }) { return true }
        return false
    }

    /// Extracts the icon file name from bundle metadata.
    private static func bundleIconName(from bundle: Bundle) -> String? {
        let infoDict = bundle.infoDictionary

        // macOS 11+ uses CFBundleIconName
        if let iconName = infoDict?["CFBundleIconName"] as? String {
            return iconName
        }

        // Older: CFBundleIconFile
        if let iconFile = infoDict?["CFBundleIconFile"] as? String {
            return iconFile.hasSuffix(".icns") ? String(iconFile.dropLast(5)) : iconFile
        }

        return nil
    }

    /// Attempts to load an icon from bundle resources.
    private static func iconFromBundle(_ bundle: Bundle, iconName: String, size: CGFloat) -> NSImage? {
        // Try the standard resource path
        if let iconPath = bundle.path(forResource: iconName, ofType: "icns") {
            if let image = NSImage(contentsOfFile: iconPath) {
                return resizeImage(image, to: size)
            }
        }
        // Try without extension in Resources
        let resourceURL = bundle.resourceURL?
            .appendingPathComponent(iconName)
            .appendingPathExtension("icns")
        if let url = resourceURL,
           let image = NSImage(contentsOfFile: url.path) {
            return resizeImage(image, to: size)
        }
        return nil
    }

    /// Generates a simple rounded-rect icon with the app's initials.
    private static func generateFallbackIcon(for name: String, size: CGFloat) -> NSImage {
        let scale: CGFloat = 2.0 // Retina
        _ = size * scale
        let image = NSImage(size: NSSize(width: size, height: size))

        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(x: 0, y: 0, width: size, height: size)

        // Background rounded rect
        let bgColor = colorForName(name)
        bgColor.setFill()
        let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.225, yRadius: size * 0.225)
        path.fill()

        // Initials text
        let initials = deriveInitials(from: name)
        let fontSize = size * 0.38
        let textColor = NSColor.white

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle,
        ]

        let textSize = (initials as NSString).size(withAttributes: attributes)
        let textRect = NSRect(
            x: (size - textSize.width) / 2,
            y: (size - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )

        (initials as NSString).draw(in: textRect, withAttributes: attributes)

        return image
    }

    /// Derives 1-2 character initials from an app name.
    private static func deriveInitials(from name: String) -> String {
        let words = name.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if words.count >= 2 {
            let first = String(words[0].prefix(1))
            let second = String(words[1].prefix(1))
            return (first + second).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    /// Deterministic color based on the app name.
    /// Note: Hasher uses a random seed per process launch, so colors are not
    /// truly deterministic across app restarts, but they are stable within a session.
    private static func colorForName(_ name: String) -> NSColor {
        let hash = abs(name.hash)
        let hue = CGFloat(hash % 360) / 360.0
        return NSColor(hue: hue, saturation: 0.55, brightness: 0.75, alpha: 1.0)
    }

    /// Resizes an NSImage to the target point size.
    private static func resizeImage(_ image: NSImage, to size: CGFloat) -> NSImage {
        let scale: CGFloat = 2.0
        let _ = size * scale
        let targetSize = NSSize(width: size, height: size)

        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        defer { resized.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )

        return resized
    }
}
