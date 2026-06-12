import Foundation

// MARK: - Notification Names

extension Notification.Name {
    static let launchpadWillOpen = Notification.Name("OpenLaunchpadWillOpen")
    static let launchpadDidClose = Notification.Name("OpenLaunchpadDidClose")
    static let launchpadCloseRequested = Notification.Name("OpenLaunchpadCloseRequested")
    static let launchpadEscapePressed = Notification.Name("OpenLaunchpadEscapePressed")
    static let launchpadKeyDown = Notification.Name("OpenLaunchpadKeyDown")
    static let launchpadAlphaNumericTyped = Notification.Name("OpenLaunchpadAlphaNumericTyped")
    static let launchpadAppsChanged = Notification.Name("OpenLaunchpadAppsChanged")
}
