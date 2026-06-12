import Carbon
import Cocoa

// MARK: - Hotkey Manager

/// Registers a global keyboard shortcut using the Carbon Event Manager.
/// Default: Option + Space. Toggles the launchpad overlay.
final class HotkeyManager {

    // MARK: - Hotkey Preference

    struct Preference {
        let keyCode: Int
        let modifiers: NSEvent.ModifierFlags

        static let `default` = Preference(
            keyCode: 49, // Space
            modifiers: .option
        )

        /// Carbon modifier flags from NSEvent.ModifierFlags.
        var carbonModifiers: UInt32 {
            var flags: UInt32 = 0
            if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
            if modifiers.contains(.option)  { flags |= UInt32(optionKey) }
            if modifiers.contains(.control) { flags |= UInt32(controlKey) }
            if modifiers.contains(.shift)   { flags |= UInt32(shiftKey) }
            return flags
        }

        var display: String {
            var parts: [String] = []
            if modifiers.contains(.command) { parts.append("⌘") }
            if modifiers.contains(.option)  { parts.append("⌥") }
            if modifiers.contains(.control) { parts.append("⌃") }
            if modifiers.contains(.shift)   { parts.append("⇧") }
            parts.append(keyCodeDisplay)
            return parts.joined()
        }

        private var keyCodeDisplay: String {
            switch keyCode {
            case 49: return "Space"
            case 53: return "Esc"
            case 36: return "Return"
            case 122: return "F1"; case 120: return "F2"
            case 99: return "F3"; case 118: return "F4"
            case 96: return "F5"; case 97: return "F6"
            case 98: return "F7"; case 100: return "F8"
            case 101: return "F9"; case 109: return "F10"
            case 103: return "F11"; case 111: return "F12"
            default: return "Key(\(keyCode))"
            }
        }
    }

    // MARK: - Properties

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    /// Retained while the Carbon event handler is installed to prevent deallocation
    /// while the handler can still fire. Released in removeHandler().
    private var selfRetainer: Unmanaged<HotkeyManager>?
    private let onTrigger: () -> Void

    // MARK: - Init

    init(preference: Preference = .default, onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
        installHandler()
        register(preference: preference)
    }

    deinit {
        unregister()
        removeHandler()
    }

    // MARK: - Registration

    /// Re-registers the hotkey with a new preference. Safe to call repeatedly.
    func register(preference: Preference) {
        unregister()

        let hotKeyID = EventHotKeyID(signature: 0x4F4C5044, id: 1) // "OLPD"
        let status = RegisterEventHotKey(
            UInt32(preference.keyCode),
            preference.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            print("[OpenLaunchpad] Failed to register hotkey (\(preference.display)): \(status)")
        } else {
            print("[OpenLaunchpad] Hotkey registered: \(preference.display)")
        }
    }

    // MARK: - Private

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { _, _, userData in
            if let userData = userData {
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                // Carbon event handlers already run on the main thread.
                manager.onTrigger()
            }
            return noErr
        }

        let retained = Unmanaged.passRetained(self)
        selfRetainer = retained
        let selfPtr = retained.toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )
        if status != noErr {
            print("[OpenLaunchpad] Failed to install hotkey handler: \(status)")
        }
    }

    private func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func removeHandler() {
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }
        // Release the retained self now that the handler is removed.
        selfRetainer?.release()
        selfRetainer = nil
    }
}
