import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private var window: LaunchpadWindow?
    private var keyMonitor: Any?
    private var hotkeyManager: HotkeyManager?
    private var appWatcher: AppDirectoryWatcher?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupWindow()
        setupKeyMonitor()
        setupMouseHoldMonitor()
        setupHotkey()
        setupGestures()
        setupAppWatcher()
        showLaunchpad()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor); keyMonitor = nil }
        GestureManager.shared.stop()
        hotkeyManager = nil
        appWatcher?.stop()
    }

    // Dock icon click → reopen
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showLaunchpad()
        return true
    }

    // MARK: - Window

    private func setupWindow() {
        let screenFrame = targetScreenFrame()
        let window = LaunchpadWindow(
            contentRect: screenFrame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.setFrame(screenFrame, display: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // .screenSaver covers the menu bar and Dock (like real Launchpad).
        // .fullScreenAuxiliary keeps it well-behaved with Mission Control & Stage Manager.
        window.level = .statusBar
        window.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        window.ignoresMouseEvents = false
        window.delegate = self

        let launchpadView = LaunchpadView(dismissAction: { [weak self] in
            // Animate window alpha out, then hide
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                self?.window?.animator().alphaValue = 0
            } completionHandler: {
                self?.hideLaunchpad()
                self?.window?.animator().alphaValue = 1.0
            }
        })
        window.contentView = NSHostingView(rootView: launchpadView)
        self.window = window
    }

    // MARK: - Key Monitor

    // MARK: - Mouse Hold (Long Press) Monitor

    /// Shared reference to the current grid layout, updated by LaunchpadView.
    /// Used to determine if a mouse hold is over an actual icon.
    static var currentGridLayoutInfo: GridLayoutInfo?

    struct GridLayoutInfo {
        let items: [(id: String, frame: CGRect)]
        let isVisible: Bool
    }

    private var mouseHoldTimer: Timer?

    private func setupMouseHoldMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self, let window = self.window, window.isVisible else { return event }
            guard let layout = AppDelegate.currentGridLayoutInfo, layout.isVisible else { return event }

            let loc = event.locationInWindow
            let windowH = window.contentLayoutRect.height

            // Quick Y-bound check
            guard loc.y >= 100 && loc.y <= windowH - 40 else { return event }

            // Only trigger if mouse is over an actual icon cell
            let hitIcon = layout.items.contains { $0.frame.contains(loc) }
            guard hitIcon else { return event }

            self.mouseHoldTimer?.invalidate()
            let timer = Timer(timeInterval: 0.5, repeats: false) { _ in
                NotificationCenter.default.post(
                    name: Notification.Name("OpenLaunchpadLongPress"), object: nil)
            }
            // .common includes .eventTracking so the timer fires even while mouse is held down
            RunLoop.main.add(timer, forMode: .common)
            self.mouseHoldTimer = timer
            return event
        }

        NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.mouseHoldTimer?.invalidate()
            self?.mouseHoldTimer = nil
            return event
        }
    }

    private func setupKeyMonitor() {
        let navKeyCodes: Set<UInt16> = [
            NavKeyCode.leftArrow.rawValue,
            NavKeyCode.rightArrow.rawValue,
            NavKeyCode.downArrow.rawValue,
            NavKeyCode.upArrow.rawValue,
            NavKeyCode.return.rawValue,
            NavKeyCode.pageUp.rawValue,
            NavKeyCode.pageDown.rawValue,
        ]
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.window?.isVisible == true else { return event }
            if let fr = self.window?.firstResponder, fr is NSTextView || fr is NSTextField {
                return event
            }
            if event.keyCode == NavKeyCode.escape.rawValue {
                NotificationCenter.default.post(name: .launchpadEscapePressed, object: nil)
                return nil
            }
            if navKeyCodes.contains(event.keyCode) {
                NotificationCenter.default.post(name: .launchpadKeyDown, object: nil, userInfo: ["keyCode": event.keyCode])
                return nil
            }
            return event
        }
        
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        hotkeyManager = HotkeyManager { [weak self] in self?.toggleLaunchpad() }
    }

    // MARK: - Gestures

    private func setupGestures() {
        guard GestureManager.isSupported else { return }
        GestureManager.shared.onPinchIn = { [weak self] in
            guard let self = self, !(self.window?.isVisible ?? false) else { return }
            self.showLaunchpad()
        }
        GestureManager.shared.onSpreadOut = { [weak self] in
            guard let self = self, self.window?.isVisible == true else { return }
            self.hideLaunchpad()
        }
        GestureManager.shared.start()
    }

    // MARK: - App Watcher

    private func setupAppWatcher() {
        appWatcher = AppDirectoryWatcher {
            NotificationCenter.default.post(name: .launchpadAppsChanged, object: nil)
        }
        appWatcher?.start()
    }

    // MARK: - Show / Hide

    func showLaunchpad() {
        guard let window = window else { return }
        let screenFrame = targetScreenFrame()
        window.setFrame(screenFrame, display: true)
        window.alphaValue = 1.0
        NotificationCenter.default.post(name: .launchpadWillOpen, object: nil)
        window.orderFront(nil)
        window.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideLaunchpad() {
        window?.orderOut(nil)
        NotificationCenter.default.post(name: .launchpadDidClose, object: nil)
    }

    private func toggleLaunchpad() {
        if window?.isVisible == true { hideLaunchpad() } else { showLaunchpad() }
    }

    // MARK: - Window Delegate

    func windowDidResignKey(_ notification: Notification) {
        guard window?.isVisible == true else { return }
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier {
            // Route through the view's animateOut() for icon zoom-out
            NotificationCenter.default.post(name: Notification.Name("OpenLaunchpadDismissRequested"), object: nil)
        }
    }

    // MARK: - Helpers

    private func targetScreenFrame() -> NSRect {
        let mouse = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let target = screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? screens.first
        return target?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
    }
}


