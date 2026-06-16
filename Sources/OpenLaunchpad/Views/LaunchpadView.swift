import SwiftUI
import UniformTypeIdentifiers

struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView(); v.blendingMode = .behindWindow; v.state = .active; v.material = .hudWindow; return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Edit Drag State

/// Tracks an active drag operation during edit (jiggle) mode.
struct EditDragState {
    let item: LaunchpadItem
    let sourceGlobalIndex: Int
    let startLocation: CGPoint
    var offset: CGSize = .zero
}

struct LaunchpadView: View {
    let dismissAction: () -> Void

    @State private var allApps: [AppItem] = []
    @State private var gridItems: [LaunchpadItem] = []
    @State private var isLoading = true
    @State private var currentPage = 0
    @State private var dragOffset: CGFloat = 0
    @State private var focusedIndex: Int? = nil
    @State private var isAnimatingIn = false
    @State private var isAnimatingOut = false

    @State private var isJiggling = false
    @State private var draggedItemID: String? = nil
    @State private var hoveredMergeTargetID: String? = nil
    @State private var expandedFolder: AppFolder? = nil
    @State private var expandedFolderApps: [AppItem] = []
    // Edit-mode drag state
    @State private var lastEdgeFlipTime: Date = .distantPast
    @State private var editDragState: EditDragState? = nil
    @State private var edgeFlipDirection: Int = 0  // -1 left, 0 none, +1 right
    @State private var folderVersion: Int = 0       // incremented on folder changes to refresh icons

    @State private var searchQuery = ""

    private var isSearching: Bool { !searchQuery.isEmpty }

    // MARK: - Cached Layout

    @State private var cachedLayout: LayoutEngine.GridLayout?
    @State private var cachedPages: [[LaunchpadItem]] = []

    /// Builds a lookup dictionary from all scanned apps for folder preview rendering.
    private var appLookup: [String: AppItem] {
        Dictionary(uniqueKeysWithValues: allApps.map { ($0.id, $0) })
    }

    private var displayItems: [LaunchpadItem] {
        guard isSearching else { return gridItems }
        let q = searchQuery.lowercased().trimmingCharacters(in: .whitespaces)
        return gridItems.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        GeometryReader { geo in
            let sw = geo.size.width
            let layout = cachedLayout ?? LayoutEngine.layout(screenWidth: sw, screenHeight: geo.size.height, itemCount: displayItems.count)
            let pages = cachedPages.isEmpty ? chunked(items: displayItems, size: layout.itemsPerPage) : cachedPages

            ZStack {
                // Blurred background
                VisualEffectView().edgesIgnoringSafeArea(.all)

                // Tap-to-dismiss layer (behind content)
                Color.clear
                    .contentShape(Rectangle())
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        if expandedFolder != nil { closeFolder() }
                        else if isSearching { searchQuery = "" }
                        else { dismissAction() }
                    }

                if isLoading {
                    loadingView
                } else if gridItems.isEmpty {
                    emptyView
                } else {
                    VStack(spacing: 0) {
                        // Search bar always visible at top
                        searchBar
                            .padding(.top, 36)

                        Spacer().frame(height: 24)

                        if isSearching {
                            searchGrid(layout: layout, sw: sw)
                        } else {
                            pageGrid(pages: pages, layout: layout, sw: sw)
                        }

                        Spacer()

                        if !isSearching {
                            bottomBar(pageCount: pages.count, sw: sw)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if expandedFolder != nil { closeFolder() }
                        else if isJiggling { withAnimation(.easeOut(duration: 0.25)) { isJiggling = false } }
                        else if isSearching { searchQuery = "" }
                        else { animateOut() }
                    }
                }

                // Floating drag icon handled in editModeOverlay

                if let folder = expandedFolder {
                    FolderView(
                        folder: folder, apps: expandedFolderApps, iconSize: layout.iconSize,
                        onClose: { closeFolder() },
                        onRename: { renameFolder(folder, newName: $0) },
                        onLaunchApp: { launchApp($0) },
                        onRemoveApp: { removeAppFromFolder($0) },
                        onReorder: { reorderAppsInFolder(folderID: folder.id, appIDs: $0) }
                    ).transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
            .opacity(isAnimatingOut ? 0.0 : (isAnimatingIn ? 1.0 : 0.0))
            .scaleEffect(isAnimatingOut ? 1.10 : (isAnimatingIn ? 1.0 : 1.10))
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenLaunchpadLongPress"))) { _ in
                withAnimation(.easeOut(duration: 0.25)) { isJiggling = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .launchpadEscapePressed)) { _ in handleEscape() }
            .onReceive(NotificationCenter.default.publisher(for: .launchpadPageSwipe)) { n in
                guard !isSearching, !isJiggling, expandedFolder == nil else { return }
                let phase = n.userInfo?["phase"] as? String
                let pageCount = cachedPages.isEmpty
                    ? chunked(items: displayItems, size: layout.itemsPerPage).count
                    : cachedPages.count

                switch phase {
                case "changed":
                    if let delta = n.userInfo?["delta"] as? CGFloat {
                        let sw = geo.size.width
                        // Clamp with rubber-banding at edges
                        let projected = delta * 0.5
                        if currentPage == 0 && projected > 0 {
                            dragOffset = projected * 0.35
                        } else if currentPage == pageCount - 1 && projected < 0 {
                            dragOffset = projected * 0.35
                        } else {
                            dragOffset = projected
                        }
                    }

                case "committed":
                    if let dir = n.userInfo?["direction"] as? Int {
                        let newPage = currentPage + dir
                        if newPage >= 0, newPage < pageCount {
                            withAnimation(.easeOut(duration: 0.25)) {
                                currentPage = newPage
                                dragOffset = 0
                                focusedIndex = nil
                            }
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                dragOffset = 0
                            }
                        }
                    }

                case "bounceback":
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        dragOffset = 0
                    }

                default: break
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenLaunchpadDismissRequested"))) { _ in animateOut() }
            .onReceive(NotificationCenter.default.publisher(for: .launchpadKeyDown)) { n in handleKeyPress(n, layout: layout) }
            .onReceive(NotificationCenter.default.publisher(for: .launchpadAppsChanged)) { _ in Task { await loadApps() } }
            .onReceive(NotificationCenter.default.publisher(for: .launchpadWillOpen)) { _ in
                searchQuery = ""; isAnimatingIn = false; isAnimatingOut = false; isJiggling = false; cachedLayout = nil; cachedPages = []
                withAnimation(.easeOut(duration: 0.35)) { isAnimatingIn = true }
            }
            .onAppear { withAnimation(.easeOut(duration: 0.35)) { isAnimatingIn = true } }
            .onChange(of: geo.size.width) { _, newWidth in
                let newLayout = LayoutEngine.layout(screenWidth: newWidth, screenHeight: geo.size.height, itemCount: displayItems.count)
                if cachedLayout?.columns != newLayout.columns || cachedLayout?.iconSize != newLayout.iconSize {
                    cachedLayout = newLayout
                    cachedPages = chunked(items: displayItems, size: newLayout.itemsPerPage)
                }
            }
            .task { await loadApps() }
        }
    }

    // MARK: - Search Bar (AppKit NSTextField for reliable input)

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.5))
                .font(.system(size: 14, weight: .medium))

            NativeSearchField(text: $searchQuery)
                .frame(height: 22)

            if !searchQuery.isEmpty {
                Button(action: { searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.5)).font(.system(size: 14))
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(width: 360)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1))
        )
    }

    // MARK: - Loading / Empty

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().scaleEffect(1.5).progressViewStyle(CircularProgressViewStyle(tint: .white))
            Text("Scanning Applications...").font(.title3).foregroundColor(.white.opacity(0.6))
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.3x3.fill").font(.system(size: 48, weight: .thin)).foregroundColor(.white.opacity(0.6))
            Text("No Applications Found").font(.title2).foregroundColor(.white.opacity(0.5))
        }
    }

    // MARK: - Search Grid

    private func searchGrid(layout: LayoutEngine.GridLayout, sw: CGFloat) -> some View {
        let cols = Array(repeating: GridItem(.fixed(layout.iconSize + 20), spacing: layout.columnSpacing), count: layout.columns)
        return ScrollView(.vertical, showsIndicators: true) {
            LazyVGrid(columns: cols, spacing: layout.rowSpacing) {
                ForEach(Array(displayItems.enumerated()), id: \.element.id) { i, item in
                    AppIconView(item: item, iconSize: layout.iconSize, isFocused: focusedIndex == i,
                        isJiggling: false, isMergeTarget: false, showLabels: true,
                        appLookup: appLookup,
                        onTap: { if case .app(let a) = item { launchApp(a) } },
                        onLongPress: { withAnimation(.easeOut(duration: 0.25)) { isJiggling = true } })
                }
            }.padding(.bottom, 40)
        }
    }

    // MARK: - Page Grid (HStack + offset, the reliable approach)

    private func pageGrid(pages: [[LaunchpadItem]], layout: LayoutEngine.GridLayout, sw: CGFloat) -> some View {
        let cols = Array(repeating: GridItem(.fixed(layout.iconSize + 20), spacing: layout.columnSpacing), count: layout.columns)

        // Publish grid item frames for hit-testing in long-press monitor
        publishGridFrames(pages: pages, layout: layout, sw: sw)

        return HStack(alignment: .top, spacing: 0) {
            ForEach(0..<pages.count, id: \.self) { pi in
                LazyVGrid(columns: cols, spacing: layout.rowSpacing) {
                    ForEach(Array(pages[pi].enumerated()), id: \.element.id) { i, item in
                        let gi = pi * layout.itemsPerPage + i
                        let dragging = draggedItemID == item.id
                        let target = hoveredMergeTargetID == item.id

                        AppIconView(item: item, iconSize: layout.iconSize,
                            isFocused: currentPage == pi && focusedIndex == gi,
                            isJiggling: isJiggling, isMergeTarget: target, showLabels: true,
                            appLookup: appLookup,
                            onTap: { if isJiggling { return }; launchItem(item) },
                            onLongPress: { withAnimation(.easeOut(duration: 0.25)) { isJiggling = true } }
                        )
                        .id(item.id + (item.id.hasPrefix("folder-") ? "-v\(folderVersion)" : ""))
                        .opacity(dragging ? 0.01 : 1.0)
                        .onDrop(of: [.text], delegate: DragRelocateDelegate(
                            item: item, items: $gridItems, draggedItemID: $draggedItemID,
                            hoveredMergeTargetID: $hoveredMergeTargetID, iconSize: layout.iconSize,
                            onChanged: saveLayout,
                            onMerge: { draggedID, target in
                                mergeItems(draggedID: draggedID, into: target)
                            }))
                        .opacity(isAnimatingIn ? 1.0 : 0.0)
                        .scaleEffect(isAnimatingIn ? 1.0 : 1.15)
                        .animation(.easeOut(duration: 0.3).delay(Double(gi) * 0.012), value: isAnimatingIn)
                    }
                }
                .frame(width: sw)
            }
        }
        .frame(width: sw * CGFloat(pages.count), alignment: .leading)
        .offset(x: -CGFloat(currentPage) * sw + dragOffset)
        .frame(width: sw, alignment: .leading)
        .compositingGroup()  // isolate page strip in its own layer — GPU handles offset changes
        .background(Color.black.opacity(0.001))
        .contentShape(Rectangle())
        .coordinateSpace(name: "pageGridSpace")
        .highPriorityGesture(swipeGesture(pages: pages, sw: sw))
        .overlay(editModeOverlay(pages: pages, layout: layout, sw: sw))

    }

    // MARK: - Swipe Gesture

    private func swipeGesture(pages: [[LaunchpadItem]], sw: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { v in
                guard !isJiggling else { return }
                let t = v.translation.width
                if currentPage == 0 && t > 0 { dragOffset = t * 0.3 }
                else if currentPage == pages.count - 1 && t < 0 { dragOffset = t * 0.3 }
                else { dragOffset = t }
            }
            .onEnded { v in
                guard !isJiggling else { return }
                let thresh: CGFloat = 80
                let vel = v.predictedEndTranslation.width
                withAnimation(.easeOut(duration: 0.25)) {
                    if vel < -thresh, currentPage < pages.count - 1 { currentPage += 1; focusedIndex = nil }
                    else if vel > thresh, currentPage > 0 { currentPage -= 1; focusedIndex = nil }
                    dragOffset = 0
                }
            }
    }

    // MARK: - Edit Mode Overlay (Drag + Edge Arrows)

    @ViewBuilder
    private func editModeOverlay(pages: [[LaunchpadItem]], layout: LayoutEngine.GridLayout, sw: CGFloat) -> some View {
        if isJiggling, expandedFolder == nil {
            ZStack {
                // Transparent drag capture layer
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 5, coordinateSpace: .local)
                            .onChanged { value in
                                handleEditDragChanged(value, layout: layout, pageCount: pages.count, sw: sw)
                            }
                            .onEnded { value in
                                handleEditDragEnded(value, layout: layout, pageCount: pages.count, sw: sw)
                            }
                    )

                // Edge navigation arrows (only when there are more pages)
                if pages.count > 1 {
                    HStack {
                        // Left edge arrow
                        if currentPage > 0 {
                            edgeArrowButton(direction: -1, sw: sw)
                        }
                        Spacer()
                        // Right edge arrow
                        if currentPage < pages.count - 1 {
                            edgeArrowButton(direction: 1, sw: sw)
                        }
                    }
                    .allowsHitTesting(false)  // let drag gesture pass through
                }

                // Floating dragged icon (follows the cursor)
                if let state = editDragState {
                    let fx = state.startLocation.x + state.offset.width
                    let fy = state.startLocation.y + state.offset.height
                    AppIconView(
                        item: state.item,
                        iconSize: layout.iconSize,
                        isFocused: false,
                        isJiggling: false,
                        isMergeTarget: false,
                        showLabels: true,
                        appLookup: appLookup,
                        onTap: {},
                        onLongPress: {}
                    )
                    .scaleEffect(1.08)
                    .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 6)
                    .position(x: fx, y: fy)
                    .allowsHitTesting(false)
                }
            }
        }
    }

    private func edgeArrowButton(direction: Int, sw: CGFloat) -> some View {
        Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
            .font(.system(size: 28, weight: .medium))
            .foregroundColor(.white.opacity(0.25))
            .frame(width: 50, height: 120)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.04))
            )
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
    }


    // MARK: - Edit Drag Handlers

    private func handleEditDragChanged(_ value: DragGesture.Value, layout: LayoutEngine.GridLayout, pageCount: Int, sw: CGFloat) {
        let loc = value.location
        let (col, row) = gridCellFromPoint(loc, layout: layout, sw: sw)

        if editDragState == nil {
            // Determine which icon is at the start location
            let pageIdx = row * layout.columns + col
            let globalIdx = currentPage * layout.itemsPerPage + pageIdx

            if globalIdx < gridItems.count {
                let item = gridItems[globalIdx]
                editDragState = EditDragState(item: item, sourceGlobalIndex: globalIdx,
                    startLocation: value.startLocation, offset: .zero)
                draggedItemID = item.id
            }
        }

        if var state = editDragState {
            state.offset = value.translation
            editDragState = state
        }

        // Show merge-target glow when hovering near the center of another cell
        updateMergeTargetHighlight(loc: loc, layout: layout, sw: sw)

        // Edge proximity detection for page flip
        let edgeWidth: CGFloat = 70
        let cooldown: TimeInterval = 0.55
        let now = Date()

        if loc.x < edgeWidth, currentPage > 0 {
            if edgeFlipDirection != -1 || now.timeIntervalSince(lastEdgeFlipTime) > cooldown {
                edgeFlipDirection = -1
                if now.timeIntervalSince(lastEdgeFlipTime) > cooldown {
                    lastEdgeFlipTime = now
                    withAnimation(.easeOut(duration: 0.2)) {
                        currentPage -= 1
                        focusedIndex = nil
                    }
                }
            }
        } else if loc.x > sw - edgeWidth, currentPage < pageCount - 1 {
            if edgeFlipDirection != 1 || now.timeIntervalSince(lastEdgeFlipTime) > cooldown {
                edgeFlipDirection = 1
                if now.timeIntervalSince(lastEdgeFlipTime) > cooldown {
                    lastEdgeFlipTime = now
                    withAnimation(.easeOut(duration: 0.2)) {
                        currentPage += 1
                        focusedIndex = nil
                    }
                }
            }
        } else {
            edgeFlipDirection = 0
        }
    }

    private func handleEditDragEnded(_ value: DragGesture.Value, layout: LayoutEngine.GridLayout, pageCount: Int, sw: CGFloat) {
        guard let state = editDragState else { return }

        let loc = value.location
        let (col, row) = gridCellFromPoint(loc, layout: layout, sw: sw)
        let targetPageIdx = row * layout.columns + col
        let targetGlobalIdx = currentPage * layout.itemsPerPage + targetPageIdx
        let clampedTarget = min(targetGlobalIdx, gridItems.count - 1)
        let sourceIdx = state.sourceGlobalIndex

        guard clampedTarget < gridItems.count, sourceIdx < gridItems.count,
              clampedTarget != sourceIdx else {
            withAnimation(.easeOut(duration: 0.2)) {
                editDragState = nil; draggedItemID = nil; edgeFlipDirection = 0
            }
            return
        }

        // Did the user drop near the CENTER of the target cell?
        // If so, merge into folder. Otherwise, reorder.
        // Folders cannot be merged — they are only reordered.
        let cellWidth = layout.iconSize + 20
        let cellHeight = layout.iconSize + 34
        let colStep = cellWidth + layout.columnSpacing
        let rowStep = cellHeight + layout.rowSpacing
        let totalGridWidth = CGFloat(layout.columns) * cellWidth + CGFloat(layout.columns - 1) * layout.columnSpacing
        let xPadding = max(0, (sw - totalGridWidth) / 2)

        let cellCenterX = xPadding + CGFloat(col) * colStep + cellWidth / 2
        let cellCenterY = CGFloat(row) * rowStep + cellHeight / 2
        let dx = abs(loc.x - cellCenterX)
        let dy = abs(loc.y - cellCenterY)
        let isNearCenter = dx < cellWidth * 0.35 && dy < cellHeight * 0.35
        let isDraggingFolder = state.item.id.hasPrefix("folder-")

        if isNearCenter,
           !isDraggingFolder,
           clampedTarget < gridItems.count,
           gridItems[clampedTarget].id != state.item.id {
            // Merge into folder (dropped ON another icon)
            mergeItems(draggedID: state.item.id, into: gridItems[clampedTarget])
        } else {
            // Reorder: insert at the target position
            let insertIdx = clampedTarget > sourceIdx ? clampedTarget + 1 : clampedTarget
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                gridItems.move(fromOffsets: IndexSet(integer: sourceIdx), toOffset: insertIdx)
            }
            saveLayout()
        }

        withAnimation(.easeOut(duration: 0.2)) {
            editDragState = nil
            draggedItemID = nil
            hoveredMergeTargetID = nil
            edgeFlipDirection = 0
        }
    }

    /// Updates `hoveredMergeTargetID` during edit-mode drag so the target cell
    /// shows a green glow when the dragged app is near its center — indicating
    /// that releasing the click will create/expand a folder.
    private func updateMergeTargetHighlight(loc: CGPoint, layout: LayoutEngine.GridLayout, sw: CGFloat) {
        guard let state = editDragState, !state.item.id.hasPrefix("folder-") else {
            if hoveredMergeTargetID != nil {
                withAnimation(.easeOut(duration: 0.2)) { hoveredMergeTargetID = nil }
            }
            return
        }

        let (col, row) = gridCellFromPoint(loc, layout: layout, sw: sw)
        let tGlobal = currentPage * layout.itemsPerPage + (row * layout.columns + col)

        guard tGlobal < gridItems.count, tGlobal != state.sourceGlobalIndex else {
            if hoveredMergeTargetID != nil {
                withAnimation(.easeOut(duration: 0.2)) { hoveredMergeTargetID = nil }
            }
            return
        }

        let cellWidth = layout.iconSize + 20
        let cellHeight = layout.iconSize + 34
        let colStep = cellWidth + layout.columnSpacing
        let rowStep = cellHeight + layout.rowSpacing
        let totalGridWidth = CGFloat(layout.columns) * cellWidth + CGFloat(layout.columns - 1) * layout.columnSpacing
        let xPad = max(0, (sw - totalGridWidth) / 2)

        let cx = xPad + CGFloat(col) * colStep + cellWidth / 2
        let cy = CGFloat(row) * rowStep + cellHeight / 2
        let nearCenter = abs(loc.x - cx) < cellWidth * 0.35 && abs(loc.y - cy) < cellHeight * 0.35

        let tid = gridItems[tGlobal].id
        if nearCenter, hoveredMergeTargetID != tid {
            withAnimation(.easeOut(duration: 0.2)) { hoveredMergeTargetID = tid }
        } else if !nearCenter, hoveredMergeTargetID == tid {
            withAnimation(.easeOut(duration: 0.2)) { hoveredMergeTargetID = nil }
        }
    }

    // MARK: - Grid Cell Calculation

    /// Converts a point in the pageGrid's local coordinate space to (column, row).
    private func gridCellFromPoint(_ pt: CGPoint, layout: LayoutEngine.GridLayout, sw: CGFloat) -> (col: Int, row: Int) {
        let cellWidth = layout.iconSize + 20    // GridItem width
        let cellHeight = layout.iconSize + 34   // icon + labelSpacing(6) + label(28)
        let colStep = cellWidth + layout.columnSpacing
        let rowStep = cellHeight + layout.rowSpacing

        let totalGridWidth = CGFloat(layout.columns) * cellWidth + CGFloat(layout.columns - 1) * layout.columnSpacing
        let xPadding = max(0, (sw - totalGridWidth) / 2)

        let col = max(0, min(layout.columns - 1, Int((pt.x - xPadding) / colStep)))
        let row = max(0, Int(pt.y / rowStep))
        return (col: col, row: row)
    }

    // MARK: - Folder Merging

    /// Merges a dragged item into a target item, creating or expanding a folder.
    /// Folders cannot be merged into other items — they are only reordered.
    private func mergeItems(draggedID: String, into target: LaunchpadItem) {
        // Guard: never merge a folder into another item
        guard !draggedID.hasPrefix("folder-") else { return }

        var fm: [UUID: AppFolder] = [:]
        for case .folder(let f, _) in gridItems { fm[f.id] = f }

        var order = gridItems.map { $0.id }
        var newFolderID: UUID? = nil

        switch target {
        case .app(let ta):
            let nf = AppFolder(name: "New Folder", appIDs: [ta.id, draggedID])
            newFolderID = nf.id
            fm[nf.id] = nf
            let fid = "folder-\(nf.id.uuidString)"
            if let ti = order.firstIndex(of: ta.id) { order.insert(fid, at: ti) }
            else { order.append(fid) }
            order.removeAll { $0 == draggedID || $0 == ta.id }

        case .folder(var tf, _):
            if !tf.appIDs.contains(draggedID) { tf.appIDs.append(draggedID); fm[tf.id] = tf }
            order.removeAll { $0 == draggedID }
        }

        // Build new items with properly resolved folder apps
        let appLookup = self.appLookup  // local copy
        
        // Collect all app IDs that live inside folders
        var folderAppIDs = Set<String>()
        for (_, f) in fm { folderAppIDs.formUnion(f.appIDs) }
        
        var newItems: [LaunchpadItem] = []
        for id in order {
            if id.hasPrefix("folder-"),
               let fid = UUID(uuidString: String(id.dropFirst(7))),
               let f = fm[fid] {
                let folderApps = f.appIDs.compactMap { appLookup[$0] }
                newItems.append(.folder(f, folderApps))
            } else if let ex = gridItems.first(where: { $0.id == id }),
                      !folderAppIDs.contains(id) {
                // Skip standalone items that are already inside a folder
                newItems.append(ex)
            }
        }

        folderVersion += 1  // trigger icon refresh for all folders

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            gridItems = newItems
        }
        saveLayout()

        // Auto-open the newly created folder and exit edit mode
        if let fid = newFolderID,
           let createdFolder = fm[fid] {
            let folderApps = createdFolder.appIDs.compactMap { appLookup[$0] }
            withAnimation(.easeOut(duration: 0.3)) {
                isJiggling = false
                expandedFolder = createdFolder
                expandedFolderApps = folderApps
            }
        }
    }

    // MARK: - Grid Frames for Hit-Testing

    private func publishGridFrames(pages: [[LaunchpadItem]], layout: LayoutEngine.GridLayout, sw: CGFloat) {
        let cellWidth = layout.iconSize + 20
        let cellHeight = layout.iconSize + 34
        let colStep = cellWidth + layout.columnSpacing
        let rowStep = cellHeight + layout.rowSpacing
        let totalGridWidth = CGFloat(layout.columns) * cellWidth + CGFloat(layout.columns - 1) * layout.columnSpacing
        let xPadding = max(0, (sw - totalGridWidth) / 2)
        let gridTop: CGFloat = 100  // search bar + spacer

        var frames: [(id: String, frame: CGRect)] = []
        for (pi, page) in pages.enumerated() {
            for (i, item) in page.enumerated() {
                let col = CGFloat(i % layout.columns)
                let row = CGFloat(i / layout.columns)
                let x = xPadding + col * colStep
                let y = gridTop + row * rowStep
                // Adjust for page offset (pageGrid starts at x=0 in local coords)
                let frame = CGRect(x: x, y: y, width: cellWidth, height: cellHeight)
                frames.append((id: item.id, frame: frame))
            }
        }

        AppDelegate.currentGridLayoutInfo = AppDelegate.GridLayoutInfo(
            items: frames,
            isVisible: !isSearching && !isLoading && expandedFolder == nil
        )
    }

    // MARK: - Bottom Bar

    private func bottomBar(pageCount: Int, sw: CGFloat) -> some View {
        HStack(spacing: 8) {
            Spacer()
            if pageCount > 1 {
                PageIndicatorView(numberOfPages: pageCount, currentPage: currentPage, dragOffset: dragOffset, screenWidth: sw, onPageTap: { page in withAnimation(.easeOut(duration: 0.25)) { currentPage = page; focusedIndex = nil } })
            }
            Spacer()
        }
        .padding(.bottom, 24)
    }

    // MARK: - Data

    private func loadApps() async {
        let apps = await Task.detached(priority: .userInitiated) { AppScanner.scanForApps() }.value
        await IconCache.shared.prewarmBatch(apps)
        let s = PersistenceManager.load(); let (r, u) = AppScanner.resolveLayout(apps: apps, layout: s)
        PersistenceManager.save(u)
        await MainActor.run { allApps = apps; gridItems = r; withAnimation(.easeOut(duration: 0.25)) { isLoading = false } }
    }

    private func refreshLayout() {
        let s = PersistenceManager.load(); let (r, u) = AppScanner.resolveLayout(apps: allApps, layout: s)
        PersistenceManager.save(u); withAnimation(.easeOut(duration: 0.2)) { gridItems = r }
    }

    private func saveLayout() { PersistenceManager.save(currentLayoutState()) }

    private func currentLayoutState() -> LayoutState {
        var m: [UUID: AppFolder] = [:]; var o: [String] = []
        for item in gridItems { switch item { case .app(let a): o.append(a.id); case .folder(let f, _): o.append("folder-\(f.id.uuidString)"); m[f.id] = f } }
        return LayoutState(orderedItemIDs: o, folders: m, hiddenAppIDs: [])
    }

    // MARK: - Launch

    private func launchItem(_ item: LaunchpadItem) {
        switch item { case .app(let a): launchApp(a); case .folder(let f, let apps): withAnimation(.easeOut(duration: 0.3)) { expandedFolder = f; expandedFolderApps = apps } }
    }
    private func launchApp(_ app: AppItem) { AppScanner.launch(app: app); dismissAction() }

    // MARK: - Folder

    private func closeFolder() { withAnimation(.easeOut(duration: 0.25)) { expandedFolder = nil; expandedFolderApps = [] } }
    private func renameFolder(_ folder: AppFolder, newName: String) {
        var s = currentLayoutState()
        if var f = s.folders[folder.id] {
            f.name = newName
            s.folders[folder.id] = f
            PersistenceManager.save(s)
            if expandedFolder?.id == folder.id { expandedFolder?.name = newName }
            rebuildGridFromState(s)
            folderVersion += 1  // refresh folder icons
        }
    }
    private func removeAppFromFolder(_ app: AppItem) {
        var s = currentLayoutState()
        for fid in s.folders.keys {
            if var f = s.folders[fid] {
                f.appIDs.removeAll { $0 == app.id }
                s.folders[fid] = f
            }
        }
        let rm = s.folders.filter { $0.value.appIDs.isEmpty }
        for fid in rm.keys { s.folders.removeValue(forKey: fid) }
        s.orderedItemIDs.removeAll { id in
            id.hasPrefix("folder-") && rm.keys.contains(UUID(uuidString: String(id.dropFirst(7))) ?? UUID())
        }
        // Add the removed app back as a standalone item at the end
        if !s.orderedItemIDs.contains(app.id) {
            s.orderedItemIDs.append(app.id)
        }
        PersistenceManager.save(s)
        rebuildGridFromState(s)
        folderVersion += 1  // refresh folder icons
        if let ef = expandedFolder, rm.keys.contains(ef.id) { closeFolder() }
        else if let ef = expandedFolder, let u = s.folders[ef.id] {
            expandedFolder = u
            expandedFolderApps = u.appIDs.compactMap { aid in allApps.first(where: { $0.id == aid }) }
        }
    }

    /// Updates the app order within a folder.
    private func reorderAppsInFolder(folderID: UUID, appIDs: [String]) {
        var s = currentLayoutState()
        guard var f = s.folders[folderID] else { return }
        // Only accept the new order if it contains the same set of apps
        guard Set(f.appIDs) == Set(appIDs) else { return }
        f.appIDs = appIDs
        s.folders[folderID] = f
        PersistenceManager.save(s)
        rebuildGridFromState(s)
        folderVersion += 1
        // Keep the expanded folder in sync
        if expandedFolder?.id == folderID {
            expandedFolder = f
            expandedFolderApps = appIDs.compactMap { aid in allApps.first(where: { $0.id == aid }) }
        }
    }

    /// Rebuilds gridItems from a LayoutState (bypasses disk I/O).
    private func rebuildGridFromState(_ state: LayoutState) {
        let appsByID = Dictionary(allApps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var items: [LaunchpadItem] = []
        for id in state.orderedItemIDs {
            if id.hasPrefix("folder-"),
               let fid = UUID(uuidString: String(id.dropFirst("folder-".count))),
               let f = state.folders[fid] {
                let folderApps = f.appIDs.compactMap { appsByID[$0] }
                if !folderApps.isEmpty {
                    items.append(.folder(f, folderApps))
                }
            } else if let app = appsByID[id] {
                items.append(.app(app))
            }
        }
        withAnimation(.easeOut(duration: 0.2)) { gridItems = items }
    }

    // MARK: - Escape

    private func handleEscape() {
        if expandedFolder != nil { closeFolder() }
        else if isSearching { searchQuery = "" }
        else if isJiggling { withAnimation(.easeOut(duration: 0.25)) { isJiggling = false } }
        else { animateOut() }
    }

    private func animateOut() {
        withAnimation(.easeOut(duration: 0.22)) { isAnimatingOut = true }
        // After SwiftUI icons zoom out, do AppKit window fade via dismissAction
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            dismissAction()
        }
    }

    // MARK: - Keyboard

    private func handleKeyPress(_ n: Notification, layout: LayoutEngine.GridLayout) {
        guard let kc = n.userInfo?["keyCode"] as? UInt16 else { return }
        if kc == NavKeyCode.return.rawValue, isSearching { if let f = displayItems.first, case .app(let a) = f { launchApp(a) }; return }
        let items = isSearching ? displayItems : LayoutEngine.itemsForPage(currentPage, items: gridItems, layout: layout)
        guard !items.isEmpty else { return }
        var i = focusedIndex ?? -1
        switch kc {
        case NavKeyCode.leftArrow.rawValue: i = i <= 0 ? items.count - 1 : i - 1
        case NavKeyCode.rightArrow.rawValue: i = i >= items.count - 1 ? 0 : i + 1
        case NavKeyCode.upArrow.rawValue: if i >= layout.columns { i -= layout.columns }
        case NavKeyCode.downArrow.rawValue: if i + layout.columns < items.count { i += layout.columns }
        case NavKeyCode.return.rawValue: if let idx = focusedIndex, idx < items.count, case .app(let a) = items[idx] { launchApp(a) }; return
        case NavKeyCode.pageUp.rawValue: if !isSearching, currentPage > 0 { withAnimation(.easeOut(duration: 0.2)) { currentPage -= 1; focusedIndex = 0 } }; return
        case NavKeyCode.pageDown.rawValue: if !isSearching, currentPage < layout.pageCount - 1 { withAnimation(.easeOut(duration: 0.2)) { currentPage += 1; focusedIndex = 0 } }; return
        default: return
        }
        focusedIndex = i
    }

    private func chunked(items: [LaunchpadItem], size: Int) -> [[LaunchpadItem]] {
        guard !items.isEmpty else { return [] }
        return stride(from: 0, to: items.count, by: size).map { Array(items[$0..<min($0 + size, items.count)]) }
    }
}

// MARK: - Drag Relocate Delegate
struct DragRelocateDelegate: DropDelegate {
    let item: LaunchpadItem
    @Binding var items: [LaunchpadItem]
    @Binding var draggedItemID: String?
    @Binding var hoveredMergeTargetID: String?
    let iconSize: CGFloat
    let onChanged: () -> Void
    /// Called when the user drops onto a target to create/expand a folder.
    /// The parent view handles the actual merge and calls onChanged afterwards.
    let onMerge: (String, LaunchpadItem) -> Void

    func dropEntered(info: DropInfo) { check(info) }
    func dropUpdated(info: DropInfo) -> DropProposal? { check(info); return DropProposal(operation: .move) }
    func dropExited(info: DropInfo) {
        if hoveredMergeTargetID == item.id {
            withAnimation(.easeOut(duration: 0.2)) { hoveredMergeTargetID = nil }
        }
    }
    func performDrop(info: DropInfo) -> Bool {
        guard let d = draggedItemID else { return false }
        // Guard: never merge a folder into another item
        guard !d.hasPrefix("folder-") else {
            withAnimation(.easeOut(duration: 0.25)) { draggedItemID = nil; hoveredMergeTargetID = nil }
            return false
        }
        if hoveredMergeTargetID == item.id {
            onMerge(d, item)
            return true
        }
        if let fi = items.firstIndex(where: { $0.id == d }),
           let ti = items.firstIndex(where: { $0.id == item.id }),
           fi != ti
        {
            withAnimation(.easeOut(duration: 0.25)) {
                items.move(fromOffsets: IndexSet(integer: fi),
                           toOffset: ti > fi ? ti + 1 : ti)
            }
        }
        withAnimation(.easeOut(duration: 0.25)) { draggedItemID = nil; hoveredMergeTargetID = nil }
        onChanged()
        return true
    }
    private func check(_ info: DropInfo) {
        guard let d = draggedItemID, d != item.id else { return }
        // Never try to merge folders — only allow reorder
        guard !d.hasPrefix("folder-") else {
            if let fi = items.firstIndex(where: { $0.id == d }),
               let ti = items.firstIndex(where: { $0.id == item.id }),
               fi != ti
            {
                withAnimation(.easeOut(duration: 0.25)) {
                    items.move(fromOffsets: IndexSet(integer: fi),
                               toOffset: ti > fi ? ti + 1 : ti)
                }
            }
            return
        }
        let cw = iconSize + 20; let ch = iconSize + 40
        let l = info.location; let mx = cw * 0.2; let my = ch * 0.2
        if l.x > mx && l.x < cw - mx && l.y > my && l.y < ch - my {
            if hoveredMergeTargetID != item.id {
                withAnimation(.easeOut(duration: 0.2)) { hoveredMergeTargetID = item.id }
            }
        } else {
            if hoveredMergeTargetID == item.id {
                withAnimation(.easeOut(duration: 0.2)) { hoveredMergeTargetID = nil }
            }
            if let fi = items.firstIndex(where: { $0.id == d }),
               let ti = items.firstIndex(where: { $0.id == item.id }),
               fi != ti
            {
                withAnimation(.easeOut(duration: 0.25)) {
                    items.move(fromOffsets: IndexSet(integer: fi),
                               toOffset: ti > fi ? ti + 1 : ti)
                }
            }
        }
    }
}

// MARK: - Native Search Field

/// AppKit NSTextField wrapper. SwiftUI's TextField inside NSHostingView
/// doesn't reliably receive keyboard events at .statusBar window level.
/// This NSTextField handles input correctly.
struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = .white
        field.font = .systemFont(ofSize: 14, weight: .medium)
        field.placeholderAttributedString = NSAttributedString(string: "Search", attributes: [.foregroundColor: NSColor.white.withAlphaComponent(0.4), .font: NSFont.systemFont(ofSize: 14, weight: .medium)])
        field.isEditable = true
        field.isSelectable = true
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NativeSearchField
        init(_ parent: NativeSearchField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                parent.text = field.stringValue
            }
        }
    }
}
