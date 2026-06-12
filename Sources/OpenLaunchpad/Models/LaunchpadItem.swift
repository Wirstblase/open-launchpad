import Foundation

// MARK: - Grid Item

/// Represents a single cell on the Launchpad grid — either an app or a folder.
enum LaunchpadItem: Identifiable {
    case app(AppItem)
    case folder(AppFolder, [AppItem])

    var id: String {
        switch self {
        case .app(let app): return app.id
        case .folder(let folder, _): return "folder-\(folder.id.uuidString)"
        }
    }

    var name: String {
        switch self {
        case .app(let app): return app.name
        case .folder(let folder, _): return folder.name
        }
    }
}
