import Cocoa

// Regular app: shows in Dock, has a Dock icon.
// Open → launchpad appears. Dismiss → app stays alive.
// Click Dock icon → launchpad reappears. Right-click → Quit.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
