import Cocoa

// MARK: - Multitouch Support Bindings

/// Raw bindings to the private MultitouchSupport.framework.
/// Loaded at runtime via dlopen/dlsym — no compile-time dependency.
/// If the framework is unavailable, gestures simply stay off.

private struct MTPoint {
    var x: Float
    var y: Float
}

private enum MTTouchLayout {
    static let stride = 96
    static let stateOffset = 20
    static let normalizedXOffset = 32
    static let normalizedYOffset = 36
    static let stateTouching: Int32 = 4
}

private typealias MTContactCallback = @convention(c) (
    UnsafeMutableRawPointer?,   // device
    UnsafeMutableRawPointer?,   // touches array
    Int32,                      // touch count
    Double,                     // timestamp
    Int32                       // frame id
) -> Int32

private typealias MTDeviceCreateListFn = @convention(c) () -> Unmanaged<CFMutableArray>?
private typealias MTCallbackRegistrationFn = @convention(c) (UnsafeMutableRawPointer?, MTContactCallback?) -> Void
private typealias MTDeviceStartFn = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Void
private typealias MTDeviceStopFn = @convention(c) (UnsafeMutableRawPointer?) -> Void

private final class MTApi {
    static let shared: MTApi? = MTApi()

    let createList: MTDeviceCreateListFn
    let registerCallback: MTCallbackRegistrationFn
    let unregisterCallback: MTCallbackRegistrationFn
    let deviceStart: MTDeviceStartFn
    let deviceStop: MTDeviceStopFn

    private init?() {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
            RTLD_NOW
        ) else { return nil }

        func sym<T>(_ name: String, _ type: T.Type) -> T? {
            guard let ptr = dlsym(handle, name) else { return nil }
            return unsafeBitCast(ptr, to: T.self)
        }

        guard let create = sym("MTDeviceCreateList", MTDeviceCreateListFn.self),
              let register = sym("MTRegisterContactFrameCallback", MTCallbackRegistrationFn.self),
              let unregister = sym("MTUnregisterContactFrameCallback", MTCallbackRegistrationFn.self),
              let start = sym("MTDeviceStart", MTDeviceStartFn.self),
              let stop = sym("MTDeviceStop", MTDeviceStopFn.self)
        else { return nil }

        createList = create
        registerCallback = register
        unregisterCallback = unregister
        deviceStart = start
        deviceStop = stop
    }
}

// MARK: - C Callback

/// One shared callback for all devices. Routes frames through the singleton.
private let gestureFrameCallback: MTContactCallback = { _, touchesPtr, touchCount, _, _ in
    var points: [MTPoint] = []
    if let touchesPtr = touchesPtr, touchCount > 0 {
        points.reserveCapacity(Int(touchCount))
        for i in 0..<Int(touchCount) {
            let touch = touchesPtr.advanced(by: i * MTTouchLayout.stride)
            let state = touch.load(fromByteOffset: MTTouchLayout.stateOffset, as: Int32.self)
            if state == MTTouchLayout.stateTouching {
                points.append(MTPoint(
                    x: touch.load(fromByteOffset: MTTouchLayout.normalizedXOffset, as: Float.self),
                    y: touch.load(fromByteOffset: MTTouchLayout.normalizedYOffset, as: Float.self)
                ))
            }
        }
    }
    GestureManager.shared.processFrame(points)
    return 0
}

// MARK: - Gesture Manager

/// Watches raw trackpad touch data and fires callbacks for pinch/spread gestures.
/// Reads from the private MultitouchSupport framework — no Accessibility permission needed.
final class GestureManager {
    static let shared = GestureManager()

    // MARK: Callbacks

    var onPinchIn: (() -> Void)?
    var onSpreadOut: (() -> Void)?

    // MARK: State

    private(set) var isEnabled = false

    static let isSupported: Bool = {
        guard let api = MTApi.shared,
              let list = api.createList()?.takeRetainedValue()
        else { return false }
        return CFArrayGetCount(list) > 0
    }()

    private var activeDevices: [UnsafeMutableRawPointer] = []
    private var deviceList: CFMutableArray?

    // Recognizer state
    private let stateLock = NSLock()
    private var gestureActive = false
    private var gestureConsumed = false
    private var initialSpread: Float = 0
    private var lastTriggerTime: TimeInterval = 0

    // Tuning constants
    private let pinchInRatio: Float = 0.62
    private let spreadOutRatio: Float = 1.45
    private let triggerCooldown: TimeInterval = 0.75

    // MARK: Init

    private init() {
        // Re-attach after system wake from sleep
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isEnabled else { return }
            self.detachDevices()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if self.isEnabled, self.activeDevices.isEmpty {
                    self.attachDevices()
                }
            }
        }
    }

    // MARK: Start / Stop

    func start() {
        isEnabled = true
        if activeDevices.isEmpty { attachDevices() }
    }

    func stop() {
        isEnabled = false
        detachDevices()
    }

    // MARK: Device Management

    private func attachDevices() {
        guard let api = MTApi.shared,
              let list = api.createList()?.takeRetainedValue()
        else { return }

        let count = CFArrayGetCount(list)
        guard count > 0 else { return }

        for i in 0..<count {
            guard let value = CFArrayGetValueAtIndex(list, i) else { continue }
            let device = UnsafeMutableRawPointer(mutating: value)
            api.registerCallback(device, gestureFrameCallback)
            api.deviceStart(device, 0)
            activeDevices.append(device)
        }
        deviceList = list
        resetRecognizer()
    }

    private func detachDevices() {
        guard let api = MTApi.shared else {
            activeDevices.removeAll()
            deviceList = nil
            return
        }
        for device in activeDevices {
            api.deviceStop(device)
            api.unregisterCallback(device, gestureFrameCallback)
        }
        activeDevices.removeAll()
        deviceList = nil
        resetRecognizer()
    }

    private func resetRecognizer() {
        stateLock.lock()
        gestureActive = false
        gestureConsumed = false
        initialSpread = 0
        stateLock.unlock()
    }

    // MARK: Frame Processing

    fileprivate func processFrame(_ touches: [MTPoint]) {
        stateLock.lock()
        defer { stateLock.unlock() }

        if touches.count >= 4 {
            let spread = averageSpread(touches)
            if !gestureActive {
                gestureActive = true
                gestureConsumed = false
                initialSpread = max(spread, 0.02)
                return
            }
            guard !gestureConsumed else { return }

            let now = Date().timeIntervalSince1970
            guard now - lastTriggerTime > triggerCooldown else { return }

            let ratio = spread / initialSpread
            if ratio < pinchInRatio {
                gestureConsumed = true
                lastTriggerTime = now
                DispatchQueue.main.async { self.onPinchIn?() }
            } else if ratio > spreadOutRatio {
                gestureConsumed = true
                lastTriggerTime = now
                DispatchQueue.main.async { self.onSpreadOut?() }
            }
        } else if touches.count <= 2 {
            gestureActive = false
            gestureConsumed = false
        }
    }

    /// Mean distance of touches from their centroid, in normalized coordinates.
    private func averageSpread(_ points: [MTPoint]) -> Float {
        let n = Float(points.count)
        var cx: Float = 0, cy: Float = 0
        for p in points { cx += p.x; cy += p.y }
        cx /= n; cy /= n

        var total: Float = 0
        for p in points {
            let dx = p.x - cx
            let dy = p.y - cy
            total += sqrt(dx * dx + dy * dy)
        }
        return total / n
    }
}
