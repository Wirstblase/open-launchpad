import SwiftUI
import UniformTypeIdentifiers

// MARK: - Folder Expanded View

/// Full overlay showing the contents of a folder with frosted glass styling.
/// Click title to rename, drag apps out to remove, click outside to close.
struct FolderView: View {
    let folder: AppFolder
    let apps: [AppItem]
    let iconSize: CGFloat
    let onClose: () -> Void
    let onRename: (String) -> Void
    let onLaunchApp: (AppItem) -> Void
    let onRemoveApp: (AppItem) -> Void

    @State private var folderName: String = ""
    @State private var isRenaming = false

    private let columns = 5
    private let rowSpacing: CGFloat = 26
    private let columnSpacing: CGFloat = 22

    var body: some View {
        ZStack {
            // Dim backdrop — tap or drop to close / remove
            Color.black.opacity(0.35)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture { onClose() }
                .onDrop(of: [UTType.text.identifier], isTargeted: nil) { providers in
                    handleBackdropDrop(providers: providers)
                    return true
                }

            VStack(spacing: 18) {
                // Editable title
                titleView

                // App grid
                folderGrid
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 30)
            .frame(minWidth: 200, maxWidth: 700)
            .background(panelBackground)
            .shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 15)
            .onAppear { folderName = folder.name }
            .onChange(of: folder.id) { _, _ in folderName = folder.name }
        }
    }

    // MARK: - Title

    private var titleView: some View {
        Group {
            if isRenaming {
                TextField("Folder Name", text: $folderName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .onSubmit {
                        commitRename()
                    }
            } else {
                Text(folderName)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
                    .onTapGesture { isRenaming = true }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(isRenaming ? 0.14 : 0))
        )
    }

    // MARK: - Grid

    private var folderGrid: some View {
        let cellWidth = iconSize + 20
        let gridItems = Array(repeating: GridItem(.fixed(cellWidth), spacing: columnSpacing), count: columns)

        return LazyVGrid(columns: gridItems, spacing: rowSpacing) {
            ForEach(apps) { app in
                FolderAppCell(
                    app: app,
                    iconSize: iconSize,
                    onLaunch: { onLaunchApp(app) },
                    onRemove: { onRemoveApp(app) }
                )
            }
        }
    }

    // MARK: - Background

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color.black.opacity(0.25))
            .background(
                VisualEffectView()
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
    }

    // MARK: - Helpers

    private func commitRename() {
        isRenaming = false
        let trimmed = folderName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            onRename(trimmed)
        } else {
            folderName = folder.name
        }
    }

    private func handleBackdropDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { data, _ in
                var path: String?
                if let data = data as? Data {
                    path = String(data: data, encoding: .utf8)
                } else if let str = data as? String {
                    path = str
                }
                if let path = path,
                   let app = apps.first(where: { $0.path == path || $0.id == path }) {
                    DispatchQueue.main.async {
                        onRemoveApp(app)
                    }
                }
            }
        }
    }
}

// MARK: - Folder App Cell

private struct FolderAppCell: View {
    let app: AppItem
    let iconSize: CGFloat
    let onLaunch: () -> Void
    let onRemove: () -> Void

    @State private var resolvedIcon: NSImage?

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let icon = resolvedIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: iconSize, height: iconSize)
                } else {
                    RoundedRectangle(cornerRadius: iconSize * 0.225)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: iconSize, height: iconSize)
                }
            }

            Text(app.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .frame(width: iconSize + 20)
        }
        .onTapGesture { onLaunch() }
        .onDrag { NSItemProvider(object: app.path as NSString) }
        .contextMenu {
            Button("Launch") { onLaunch() }
            Divider()
            Button("Remove from Folder") { onRemove() }
        }
        .task {
            resolvedIcon = await IconCache.shared.icon(for: app)
        }
    }
}
