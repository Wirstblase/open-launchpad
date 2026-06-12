import Foundation

// MARK: - App Directory Watcher

/// Monitors standard macOS application directories for changes using FSEvents.
/// When an .app bundle is added, removed, or modified, the `onChanged` callback is invoked
/// after a 1-second debounce.
final class AppDirectoryWatcher {
    private let onChanged: () -> Void
    private var stream: FSEventStreamRef?
    private var debounceWorkItem: DispatchWorkItem?

    init(onChanged: @escaping () -> Void) { self.onChanged = onChanged }

    deinit {
        stop()
    }

    func start() {
        guard stream == nil else { return }
        let paths = ["/Applications", "/Applications/Utilities", "/System/Applications", NSHomeDirectory() + "/Applications"] as CFArray
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let cb: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info = info else { return }
            Unmanaged<AppDirectoryWatcher>.fromOpaque(info).takeUnretainedValue().scheduleNotify()
        }
        stream = FSEventStreamCreate(kCFAllocatorDefault, cb, &ctx, paths, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 2.0, FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents))
        if let s = stream {
            FSEventStreamSetDispatchQueue(s, DispatchQueue.main)
            FSEventStreamStart(s)
        } else {
            print("[OpenLaunchpad] WARNING: Failed to create FSEventStream for app directories")
        }
    }

    func stop() {
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            stream = nil
        }
    }

    private func scheduleNotify() {
        debounceWorkItem?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.onChanged() }
        debounceWorkItem = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: w)
    }
}
