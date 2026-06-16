import SwiftUI
import UniformTypeIdentifiers

// MARK: - Folder Expanded View

/// Full overlay showing the contents of a folder with frosted glass styling.
/// Click title to rename, drag apps to reorder, drag outside to remove, click outside to close.
struct FolderView: View {
    let folder: AppFolder
    let apps: [AppItem]
    let iconSize: CGFloat
    let onClose: () -> Void
    let onRename: (String) -> Void
    let onLaunchApp: (AppItem) -> Void
    let onRemoveApp: (AppItem) -> Void
    let onReorder: ([String]) -> Void

    @State private var folderName: String = ""
    @State private var isRenaming = false

    // Drag state
    @State private var orderedAppIDs: [String] = []
    @State private var draggedAppID: String? = nil
    @State private var dragOffset: CGSize = .zero
    @State private var dragSourceIndex: Int = -1
    @State private var isDraggedOutsidePanel = false
    @State private var panelFrame: CGRect = .zero
    @State private var lastReorderIndex: Int = -1

    private let columns = 5
    private let rowSpacing: CGFloat = 26
    private let columnSpacing: CGFloat = 22

    private var appLookup: [String: AppItem] {
        Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
    }

    var body: some View {
        ZStack {
            // Dim backdrop — rendered at an enormous size so that even when the
            // FolderView is animating in at 0.85 scale, the backdrop still covers
            // the entire screen edge-to-edge with no visible borders.
            Color.black.opacity(0.35)
                .frame(width: 8000, height: 8000)
                .position(x: 0, y: 0)
                .onTapGesture { onClose() }
                .onDrop(of: [UTType.text.identifier], isTargeted: nil) { providers in
                    handleBackdropDrop(providers: providers)
                    return true
                }
                .accessibilityLabel("Close folder")
                .accessibilityHint("Tap or drop apps outside the folder to close it")

            VStack(spacing: 18) {
                titleView
                folderGridContent
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 30)
            .frame(minWidth: 200, maxWidth: 700)
            .background(panelBackground)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { panelFrame = geo.frame(in: .global) }
                        .onChange(of: geo.frame(in: .global)) { _, newFrame in
                            panelFrame = newFrame
                        }
                }
            )
            .shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 15)
            .onAppear {
                folderName = folder.name
                orderedAppIDs = apps.map(\.id)
            }
            .onChange(of: folder.id) { _, _ in
                folderName = folder.name
                orderedAppIDs = apps.map(\.id)
            }
            .coordinateSpace(name: "folderPanel")
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
                    .onSubmit { commitRename() }
                    .accessibilityLabel("Folder name")
                    .accessibilityHint("Edit the folder name and press Return to confirm")
            } else {
                Text(folderName)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
                    .onTapGesture { isRenaming = true }
                    .accessibilityLabel(folderName)
                    .accessibilityHint("Tap to rename folder")
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(isRenaming ? 0.14 : 0))
        )
    }

    // MARK: - Grid Content

    private var folderGridContent: some View {
        let cellWidth = iconSize + 20
        let gridColumns = Array(repeating: GridItem(.fixed(cellWidth), spacing: columnSpacing), count: columns)

        return ZStack(alignment: .topLeading) {
            // The actual grid of cells — dragged cell is hidden at its original position
            LazyVGrid(columns: gridColumns, spacing: rowSpacing) {
                ForEach(Array(orderedAppIDs.enumerated()), id: \.element) { index, appID in
                    if let app = appLookup[appID] {
                        FolderAppCell(
                            app: app,
                            iconSize: iconSize,
                            isDragged: draggedAppID == appID,
                            isOutsidePanel: draggedAppID == appID && isDraggedOutsidePanel,
                            onTap: { onLaunchApp(app) }
                        )
                        .opacity(draggedAppID == appID ? 0.0 : 1.0)
                        .contextMenu {
                            Button("Launch") { onLaunchApp(app) }
                            Divider()
                            Button("Remove from Folder") { onRemoveApp(app) }
                        }
                    }
                }
            }

            // Floating dragged icon — positioned from the source cell's grid location
            if let draggedID = draggedAppID, let app = appLookup[draggedID] {
                let cellW = iconSize + 20
                let cellH = iconSize + 34
                let col = dragSourceIndex % columns
                let row = dragSourceIndex / columns
                let baseX = CGFloat(col) * (cellW + columnSpacing)
                let baseY = CGFloat(row) * (cellH + rowSpacing)

                FolderAppCell(
                    app: app,
                    iconSize: iconSize,
                    isDragged: true,
                    isOutsidePanel: isDraggedOutsidePanel,
                    onTap: {}
                )
                .scaleEffect(1.08)
                .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 4)
                .offset(x: baseX + dragOffset.width,
                        y: baseY + dragOffset.height)
                .allowsHitTesting(false)
            }
        }
        .gesture(folderDragGesture(cellWidth: cellWidth))
    }

    // MARK: - Drag Gesture

    private func folderDragGesture(cellWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("folderPanel"))
            .onChanged { value in
                if draggedAppID == nil {
                    // Determine which cell the drag started on
                    let hitIndex = cellIndexAt(value.startLocation, cellWidth: cellWidth)
                    if hitIndex >= 0, hitIndex < orderedAppIDs.count {
                        draggedAppID = orderedAppIDs[hitIndex]
                        dragSourceIndex = hitIndex
                        lastReorderIndex = hitIndex
                    }
                }

                guard draggedAppID != nil else { return }
                dragOffset = value.translation

                // Detect if drag has left the folder panel bounds
                let loc = value.location
                let margin: CGFloat = 30
                isDraggedOutsidePanel = loc.x < -margin
                    || loc.x > panelFrame.width + margin
                    || loc.y < -margin
                    || loc.y > panelFrame.height + margin

                // Reorder: if inside the panel, check which cell the drag is hovering over
                if !isDraggedOutsidePanel, let draggedID = draggedAppID {
                    let targetIndex = cellIndexAt(value.location, cellWidth: cellWidth)
                    if targetIndex >= 0, targetIndex < orderedAppIDs.count,
                       targetIndex != lastReorderIndex,
                       let currentIndex = orderedAppIDs.firstIndex(of: draggedID),
                       targetIndex != currentIndex
                    {
                        withAnimation(.easeOut(duration: 0.18)) {
                            orderedAppIDs.move(
                                fromOffsets: IndexSet(integer: currentIndex),
                                toOffset: targetIndex > currentIndex ? targetIndex + 1 : targetIndex
                            )
                        }
                        lastReorderIndex = targetIndex > currentIndex ? targetIndex - 1 : targetIndex
                    }
                }
            }
            .onEnded { value in
                defer {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        draggedAppID = nil
                        dragOffset = .zero
                        dragSourceIndex = -1
                        isDraggedOutsidePanel = false
                        lastReorderIndex = -1
                    }
                }

                guard let draggedID = draggedAppID else { return }

                if isDraggedOutsidePanel, let app = appLookup[draggedID] {
                    // App dragged outside the folder — remove it
                    onRemoveApp(app)
                } else if orderedAppIDs != apps.map(\.id) {
                    // Order changed — persist the new order
                    onReorder(orderedAppIDs)
                }
            }
    }

    /// Returns the index in the orderedAppIDs array for a given point within the folder panel.
    private func cellIndexAt(_ point: CGPoint, cellWidth: CGFloat) -> Int {
        let cellH = iconSize + 34   // icon + label
        let colStep = cellWidth + columnSpacing
        let rowStep = cellH + rowSpacing

        let col = max(0, Int(point.x / colStep))
        let row = max(0, Int(point.y / rowStep))

        // Clamp column to valid range
        let clampedCol = min(col, columns - 1)
        return row * columns + clampedCol
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
    let isDragged: Bool
    let isOutsidePanel: Bool
    let onTap: () -> Void

    @State private var resolvedIcon: NSImage?

    var body: some View {
        VStack(spacing: 6) {
            // Icon
            Group {
                if let icon = resolvedIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconSize, height: iconSize)
                } else {
                    RoundedRectangle(cornerRadius: iconSize * 0.225)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: iconSize, height: iconSize)
                }
            }
            // When dragged outside the panel, desaturate + fade to signal removal
            .saturation(isOutsidePanel ? 0.0 : 1.0)
            .opacity(isOutsidePanel ? 0.45 : 1.0)

            // Label
            Text(app.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .frame(width: iconSize + 20)
                .opacity(isOutsidePanel ? 0.4 : 1.0)
        }
        .frame(width: iconSize + 20)
        .accessibilityLabel(app.name)
        .accessibilityHint("Tap to launch, drag to reorder or drag outside to remove from folder")
        .accessibilityAddTraits(.isButton)
        .onTapGesture { onTap() }
        .task {
            resolvedIcon = await IconCache.shared.icon(for: app)
        }
    }
}

