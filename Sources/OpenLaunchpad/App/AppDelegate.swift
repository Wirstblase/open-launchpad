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
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.ignoresMouseEvents = false
        window.delegate = self

        let launchpadView = LaunchpadView(dismissAction: { [weak self] in
            self?.hideLaunchpad()
        })
        window.contentView = NSHostingView(rootView: launchpadView)
        self.window = window
    }

    // MARK: - Key Monitor

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
        // Only hide if another app (not a system panel) became frontmost.
        // This prevents the launchpad from vanishing when system dialogs,
        // Notification Center, or Stage Manager temporarily steal focus.
        guard window?.isVisible == true else { return }
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier {
            hideLaunchpad()
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


