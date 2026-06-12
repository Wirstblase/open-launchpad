import SwiftUI
import UniformTypeIdentifiers

struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView(); v.blendingMode = .behindWindow; v.state = .active; v.material = .hudWindow; return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
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
    @State private var edgeFlipTimer: Timer? = nil
    @State private var lastEdgeFlipTime: Date = .distantPast

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
                        else if isSearching { searchQuery = "" }
                        else { animateOut() }
                    }
                }

                if let folder = expandedFolder {
                    FolderView(
                        folder: folder, apps: expandedFolderApps, iconSize: layout.iconSize,
                        onClose: { closeFolder() },
                        onRename: { renameFolder(folder, newName: $0) },
                        onLaunchApp: { launchApp($0) },
                        onRemoveApp: { removeAppFromFolder($0) }
                    ).transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
            .opacity(isAnimatingOut ? 0.0 : (isAnimatingIn ? (expandedFolder != nil ? 0.4 : 1.0) : 0.0))
            .scaleEffect(isAnimatingOut ? 1.10 : (isAnimatingIn ? 1.0 : 1.10))
            .onReceive(NotificationCenter.default.publisher(for: .launchpadEscapePressed)) { _ in handleEscape() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenLaunchpadDismissRequested"))) { _ in animateOut() }
            .onReceive(NotificationCenter.default.publisher(for: .launchpadKeyDown)) { n in handleKeyPress(n, layout: layout) }
            .onReceive(NotificationCenter.default.publisher(for: .launchpadAppsChanged)) { _ in Task { await loadApps() } }
            .onReceive(NotificationCenter.default.publisher(for: .launchpadWillOpen)) { _ in
                searchQuery = ""; isAnimatingIn = false; isAnimatingOut = false; cachedLayout = nil; cachedPages = []
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
                        onLongPress: {})
                }
            }.padding(.bottom, 40)
        }
    }

    // MARK: - Page Grid (HStack + offset, the reliable approach)

    private func pageGrid(pages: [[LaunchpadItem]], layout: LayoutEngine.GridLayout, sw: CGFloat) -> some View {
        let cols = Array(repeating: GridItem(.fixed(layout.iconSize + 20), spacing: layout.columnSpacing), count: layout.columns)

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
                        .opacity(dragging ? 0.01 : 1.0)
                        .onDrop(of: [UTType.text.identifier], delegate: DragRelocateDelegate(
                            item: item, items: $gridItems, draggedItemID: $draggedItemID,
                            hoveredMergeTargetID: $hoveredMergeTargetID, iconSize: layout.iconSize, onChanged: saveLayout))
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
        .background(Color.black.opacity(0.001))
        .contentShape(Rectangle())
        .highPriorityGesture(swipeGesture(pages: pages, sw: sw))
        .onChange(of: draggedItemID) { _, v in
            if v != nil, expandedFolder == nil { startEdgeMonitor(sw: sw, pageCount: pages.count) }
            else { stopEdgeMonitor() }
        }
        .onDisappear { stopEdgeMonitor() }
    }

    // MARK: - Swipe Gesture

    private func swipeGesture(pages: [[LaunchpadItem]], sw: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { v in
                let t = v.translation.width
                if currentPage == 0 && t > 0 { dragOffset = t * 0.3 }
                else if currentPage == pages.count - 1 && t < 0 { dragOffset = t * 0.3 }
                else { dragOffset = t }
            }
            .onEnded { v in
                let thresh: CGFloat = 80
                let vel = v.predictedEndTranslation.width
                withAnimation(.easeOut(duration: 0.25)) {
                    if vel < -thresh, currentPage < pages.count - 1 { currentPage += 1; focusedIndex = nil }
                    else if vel > thresh, currentPage > 0 { currentPage -= 1; focusedIndex = nil }
                    dragOffset = 0
                }
            }
    }

    // MARK: - Edge Monitor

    private func startEdgeMonitor(sw: CGFloat, pageCount: Int) {
        stopEdgeMonitor(); lastEdgeFlipTime = .distantPast
        edgeFlipTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard self.draggedItemID != nil, self.expandedFolder == nil else { return }
            guard Date().timeIntervalSince(self.lastEdgeFlipTime) >= 0.8 else { return }
            guard let w = NSApp.windows.first(where: { $0.isVisible && $0.level == .modalPanel }) else { return }
            let mx = NSEvent.mouseLocation.x; let f = w.frame
            if mx <= f.minX + 44, self.currentPage > 0 { self.lastEdgeFlipTime = Date(); self.currentPage -= 1; self.focusedIndex = nil }
            else if mx >= f.maxX - 44, self.currentPage < pageCount - 1 { self.lastEdgeFlipTime = Date(); self.currentPage += 1; self.focusedIndex = nil }
        }
        RunLoop.main.add(edgeFlipTimer!, forMode: .common)
    }

    private func stopEdgeMonitor() { edgeFlipTimer?.invalidate(); edgeFlipTimer = nil }

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
        if s.folders[folder.id] != nil { s.folders[folder.id]?.name = newName; PersistenceManager.save(s); if expandedFolder?.id == folder.id { expandedFolder?.name = newName }; refreshLayout() }
    }
    private func removeAppFromFolder(_ app: AppItem) {
        var s = currentLayoutState()
        for fid in s.folders.keys { s.folders[fid]?.appIDs.removeAll { $0 == app.id } }
        let rm = s.folders.filter { $0.value.appIDs.isEmpty }; for fid in rm.keys { s.folders.removeValue(forKey: fid) }
        s.orderedItemIDs.removeAll { id in id.hasPrefix("folder-") && rm.keys.contains(UUID(uuidString: String(id.dropFirst(7))) ?? UUID()) }
        PersistenceManager.save(s); refreshLayout()
        if let ef = expandedFolder, rm.keys.contains(ef.id) { closeFolder() }
        else if let ef = expandedFolder, let u = s.folders[ef.id] {
            expandedFolder = u
            let apps = allApps
            expandedFolderApps = u.appIDs.compactMap { aid in apps.first(where: { $0.id == aid }) }
        }
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
    let item: LaunchpadItem; @Binding var items: [LaunchpadItem]; @Binding var draggedItemID: String?
    @Binding var hoveredMergeTargetID: String?; let iconSize: CGFloat; let onChanged: () -> Void
    func dropEntered(info: DropInfo) { check(info) }
    func dropUpdated(info: DropInfo) -> DropProposal? { check(info); return DropProposal(operation: .move) }
    func dropExited(info: DropInfo) { if hoveredMergeTargetID == item.id { withAnimation(.easeOut(duration: 0.2)) { hoveredMergeTargetID = nil } } }
    func performDrop(info: DropInfo) -> Bool {
        guard let d = draggedItemID else { return false }
        if hoveredMergeTargetID == item.id { merge(d, item); return true }
        if let fi = items.firstIndex(where: { $0.id == d }), let ti = items.firstIndex(where: { $0.id == item.id }), fi != ti {
            withAnimation(.easeOut(duration: 0.25)) { items.move(fromOffsets: IndexSet(integer: fi), toOffset: ti > fi ? ti + 1 : ti) }
        }
        withAnimation(.easeOut(duration: 0.25)) { draggedItemID = nil; hoveredMergeTargetID = nil }; onChanged(); return true
    }
    private func check(_ info: DropInfo) {
        guard draggedItemID != nil, draggedItemID != item.id else { return }
        let cw = iconSize + 20; let ch = iconSize + 40; let l = info.location; let mx = cw * 0.2; let my = ch * 0.2
        if l.x > mx && l.x < cw - mx && l.y > my && l.y < ch - my {
            if hoveredMergeTargetID != item.id { withAnimation(.easeOut(duration: 0.2)) { hoveredMergeTargetID = item.id } }
        } else {
            if hoveredMergeTargetID == item.id { withAnimation(.easeOut(duration: 0.2)) { hoveredMergeTargetID = nil } }
            if let d = draggedItemID, let fi = items.firstIndex(where: { $0.id == d }), let ti = items.firstIndex(where: { $0.id == item.id }), fi != ti {
                withAnimation(.easeOut(duration: 0.25)) { items.move(fromOffsets: IndexSet(integer: fi), toOffset: ti > fi ? ti + 1 : ti) }
            }
        }
    }
    private func merge(_ dragged: String, _ target: LaunchpadItem) {
        var fm: [UUID: AppFolder] = [:]; for case .folder(let f, _) in items { fm[f.id] = f }
        var o = items.map { $0.id }
        switch target {
        case .app(let ta): let nf = AppFolder(name: "New Folder", appIDs: [ta.id, dragged]); fm[nf.id] = nf; let fid = "folder-\(nf.id.uuidString)"; if let ti = o.firstIndex(of: ta.id) { o.insert(fid, at: ti) } else { o.append(fid) }; o.removeAll { $0 == dragged || $0 == ta.id }
        case .folder(var tf, _): if !tf.appIDs.contains(dragged) { tf.appIDs.append(dragged); fm[tf.id] = tf }; o.removeAll { $0 == dragged }
        }
        var ni: [LaunchpadItem] = []
        for id in o { if id.hasPrefix("folder-"), let fid = UUID(uuidString: String(id.dropFirst(7))), let f = fm[fid] { ni.append(.folder(f, [])) } else if let ex = items.first(where: { $0.id == id }) { ni.append(ex) } }
        withAnimation(.easeOut(duration: 0.25)) { items = ni; draggedItemID = nil; hoveredMergeTargetID = nil }; onChanged()
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
