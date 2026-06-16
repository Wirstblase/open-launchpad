import AppKit
import CoreGraphics

// MARK: - Background Capture

/// Captures the desktop behind the launchpad window ONCE (on open),
/// applies a Gaussian blur, and caches the result per screen.
/// This replaces the per-frame .behindWindow NSVisualEffectView sampling
/// which destroys GPU performance on Intel Macs.
///
/// Note: CGWindowListCreateImage triggers a one-time Screen Recording
/// permission prompt on macOS 10.15+. Once granted, subsequent captures
/// are silent.
enum BackgroundCapture {

    private static var cachedImage: NSImage?
    private static var cachedScreenFrame: CGRect = .zero

    /// Captures and blurs the desktop for the given screen.
    /// Result is cached; call `invalidate()` to force a re-capture.
    static func capture(for screen: NSScreen) -> NSImage? {
        let frame = screen.frame

        if let cached = cachedImage, cachedScreenFrame == frame {
            return cached
        }

        guard let cgImage = captureScreen(screen) else {
            return nil
        }

        guard let blurred = applyBlur(to: cgImage) else {
            let img = NSImage(cgImage: cgImage, size: frame.size)
            cachedImage = img
            cachedScreenFrame = frame
            return img
        }

        let img = NSImage(cgImage: blurred, size: frame.size)
        cachedImage = img
        cachedScreenFrame = frame
        return img
    }

    /// Discards the cached image.
    static func invalidate() {
        cachedImage = nil
        cachedScreenFrame = .zero
    }

    // MARK: - Private

    private static func captureScreen(_ screen: NSScreen) -> CGImage? {
        // Capture the screen bounds at nominal resolution.
        // The image will be display-native pixels (2x on Retina).
        // NSImage(cgImage:size:) handles the point-size mapping.
        return CGWindowListCreateImage(
            screen.frame,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .nominalResolution
        )
    }

    private static func applyBlur(to image: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: image)
        guard let blurred = CIFilter(name: "CIGaussianBlur", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputRadiusKey: 40.0
        ])?.outputImage else { return nil }

        // Darken to match .hudWindow material
        let output = CIFilter(name: "CIExposureAdjust", parameters: [
            kCIInputImageKey: blurred,
            kCIInputEVKey: -0.6
        ])?.outputImage ?? blurred

        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        return ctx.createCGImage(output, from: output.extent)
    }
}
