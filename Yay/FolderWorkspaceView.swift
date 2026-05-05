import SwiftUI
import Combine
import AppKit
import YayCore
import YayExport
import YayTextEditor
import YayPreview

/// Workspace window opened via File > Open Folder. Sidebar lists files in the
/// folder; right pane is a tab strip plus the editor + preview. Each opened
/// file is its own tab — clicking a sidebar entry opens (or activates) a tab,
/// it does not replace the previous one.
struct FolderWorkspaceView: View {
    let folderURL: URL

    @State private var openFiles: [OpenFile] = []
    @State private var activeFileURL: URL?
    @State private var sidebarSelection: URL?

    @State private var pendingClose: URL?
    @State private var loadError: String?
    @State private var didStartAccess = false

    // Sidebar create-entry prompt state.
    @State private var createTarget: CreateRequest?
    @State private var newEntryName: String = ""
    /// Increments after every disk mutation to force the sidebar to re-read
    /// its tree (OutlineGroup caches the snapshot otherwise).
    @State private var sidebarRefreshToken = UUID()

    @State private var renameTarget: URL?
    @State private var renameText: String = ""
    @State private var trashTargets: [URL]?

    @AppStorage("editorFontFamily") private var fontFamily = "Menlo"
    @AppStorage("editorFontSize") private var fontSize: Double = 14
    @AppStorage("editorLineHeight") private var lineHeight: Double = 1.5

    @State private var showPreview = false
    @State private var previewMode: PreviewMode = .split
    @State private var splitRatio: CGFloat = 0.5
    @StateObject private var scrollSync = ScrollSyncBridge()
    @State private var scrollSyncCancellables: Set<AnyCancellable> = []
    @StateObject private var fileWatcher = FileWatcher()

    private var editorConfiguration: YayEditorConfiguration {
        let theme = MarkdownTheme.withFont(family: fontFamily, size: fontSize, basedOn: .githubLight)
        return YayEditorConfiguration(
            theme: theme,
            lineFragmentPadding: 5,
            textContainerInset: NSSize(width: 5, height: 5),
            lineHeightMultiple: lineHeight,
            enablesLiveHighlighting: true,
            focusOnAppear: true
        )
    }

    private var activeIndex: Int? {
        guard let activeFileURL else { return nil }
        return openFiles.firstIndex(where: { $0.url == activeFileURL })
    }
    private var activeFile: OpenFile? { activeIndex.map { openFiles[$0] } }
    private var hasDirtyActive: Bool { activeFile?.isDirty ?? false }
    var body: some View {
        navigationSplitView
            .focusedSceneValue(\.markdownExport, exportContext)
            .background(WindowExportContextWriter(context: exportContext))
            .focusedSceneValue(\.folderSave, FolderSaveAction(canSave: hasDirtyActive, perform: { save() }))
            .focusedSceneValue(\.folderCloseTab, FolderCloseTabAction(canClose: activeFileURL != nil, perform: { closeActiveTab() }))
            .onAppear {
                startAccess()
                wireFileWatcher()
            }
            .onDisappear { stopAccess(); fileWatcher.unwatchAll() }
            .onChange(of: sidebarSelection) { _, newValue in
                handleSelectionChange(to: newValue)
            }
            .alert("Discard unsaved changes?", isPresented: Binding(
                get: { pendingClose != nil },
                set: { if !$0 { pendingClose = nil } }
            ), presenting: pendingClose) { url in
                Button("Save") {
                    save(url: url)
                    performClose(url)
                }
                Button("Discard", role: .destructive) {
                    performClose(url)
                }
                Button("Cancel", role: .cancel) {}
            } message: { url in
                Text("\(url.lastPathComponent) has unsaved changes.")
            }
            .alert("Couldn't open file", isPresented: Binding(
                get: { loadError != nil },
                set: { if !$0 { loadError = nil } }
            ), presenting: loadError) { _ in
                Button("OK") { loadError = nil }
            } message: { message in
                Text(message)
            }
            .alert(createTarget?.kind == .folder ? "New Folder" : "New File",
                   isPresented: Binding(
                         get: { createTarget != nil },
                         set: { if !$0 { createTarget = nil } }
                   ),
                   presenting: createTarget) { request in
                TextField("Name", text: $newEntryName)
                Button("Create") { performCreate(request) }
                Button("Cancel", role: .cancel) {}
            } message: { request in
                Text("Create in \(request.directory.lastPathComponent)")
            }
            .alert("Rename",
                   isPresented: Binding(
                         get: { renameTarget != nil },
                         set: { if !$0 { renameTarget = nil } }
                   ),
                   presenting: renameTarget) { _ in
                TextField("Name", text: $renameText)
                Button("Rename") { performRename() }
                Button("Cancel", role: .cancel) {}
            } message: { url in
                Text("Enter a new name for \(url.lastPathComponent)")
            }
            .alert("Move to Trash?",
                   isPresented: Binding(
                         get: { trashTargets != nil },
                         set: { if !$0 { trashTargets = nil } }
                   ),
                   presenting: trashTargets) { urls in
                Button("Move to Trash", role: .destructive) { performTrash(urls) }
                Button("Cancel", role: .cancel) {}
            } message: { urls in
                Text(trashConfirmationMessage(for: urls))
            }
    }

    private var navigationSplitView: some View {
        NavigationSplitView {
            FolderSidebar(
                rootURL: folderURL,
                selection: $sidebarSelection,
                onCreate: { directory, kind in
                    createTarget = CreateRequest(directory: directory, kind: kind)
                    newEntryName = (kind == .file) ? "Untitled.md" : "New Folder"
                },
                onRename: { url in
                    renameTarget = url
                    renameText = url.lastPathComponent
                },
                onTrash: { urls in
                    trashTargets = urls
                },
                onDuplicate: { url in
                    performDuplicate(url)
                },
                onMove: { sources, destFolder in
                    performMove(sources: sources, destFolder: destFolder)
                },
                onReveal: { url in
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            )
            .id(sidebarRefreshToken)
            .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 400)
        } detail: {
            detailPane
                .padding(.leading, 8)
                .navigationTitle(folderURL.lastPathComponent)
                .navigationSubtitle(folderURL.path)
        }
    }

    // MARK: - Detail pane

    @ViewBuilder
    private var detailPane: some View {
        VStack(spacing: 0) {
            if !openFiles.isEmpty {
                TabStrip(
                    files: openFiles,
                    activeURL: activeFileURL,
                    onSelect: { activeFileURL = $0 },
                    onClose: { requestClose($0) }
                )
                Divider()
            }

            if activeIndex != nil {
                editorAndPreview
                    .onReceive(NotificationCenter.default.publisher(for: .togglePreview)) { _ in
                        showPreview.toggle()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .setPreviewModeSplit)) { _ in
                        previewMode = .split
                        showPreview = true
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .setPreviewModeFull)) { _ in
                        previewMode = .full
                        showPreview = true
                    }
            } else {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("Select a file from the sidebar")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var editorAndPreview: some View {
        // Reset the editor/preview view tree per active tab so NSTextView
        // state (undo, scroll, highlight cache) doesn't bleed between files.
        let activeURL = activeFileURL ?? folderURL
        GeometryReader { geo in
            if showPreview && previewMode == .split {
                let dividerX = geo.size.width * splitRatio
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        YayTextEditor(text: textBinding, configuration: editorConfiguration, scrollSync: scrollSync)
                            .frame(width: dividerX)

                        MarkdownPreviewView(
                            markdown: textBinding.wrappedValue,
                            baseURL: activeFileURL?.deletingLastPathComponent(),
                            scrollSync: scrollSync
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    SplitDivider()
                        .frame(height: geo.size.height)
                        .offset(x: dividerX - 6)
                        .gesture(
                            DragGesture(minimumDistance: 1, coordinateSpace: .named("folderSplit"))
                                .onChanged { value in
                                    let ratio = value.location.x / geo.size.width
                                    splitRatio = min(max(ratio, 0.2), 0.8)
                                }
                        )
                }
                .coordinateSpace(name: "folderSplit")
            } else if showPreview {
                MarkdownPreviewView(
                    markdown: textBinding.wrappedValue,
                    baseURL: activeFileURL?.deletingLastPathComponent(),
                    scrollSync: scrollSync
                )
            } else {
                YayTextEditor(text: textBinding, configuration: editorConfiguration, scrollSync: scrollSync)
            }
        }
        .id(activeURL)  // hard-recreate per tab — see comment above
        .onAppear { wireScrollSync() }
    }

    // MARK: - Bindings

    /// Looking up by URL on every get/set rather than caching an index keeps
    /// the binding valid across `openFiles` mutations (close other tab,
    /// reorder, etc.) without dangling indices.
    private var textBinding: Binding<String> {
        Binding(
            get: {
                guard let activeFileURL else { return "" }
                return openFiles.first(where: { $0.url == activeFileURL })?.text ?? ""
            },
            set: { newValue in
                guard let activeFileURL,
                      let idx = openFiles.firstIndex(where: { $0.url == activeFileURL })
                else { return }
                openFiles[idx].text = newValue
            }
        )
    }

    // MARK: - Export context

    private var exportContext: MarkdownExportContext? {
        guard let activeFile else { return nil }
        let baseName = activeFile.url.deletingPathExtension().lastPathComponent
        return MarkdownExportContext(text: activeFile.text, suggestedFilename: baseName + ".html", fileURL: activeFile.url)
    }

    // MARK: - Sidebar selection

    private func handleSelectionChange(to newURL: URL?) {
        guard let newURL else { return }
        if openFiles.contains(where: { $0.url == newURL }) {
            activeFileURL = newURL
            return
        }
        openTab(for: newURL)
    }

    private func openTab(for url: URL) {
        // Cloud placeholders (OneDrive, iCloud, etc.) that haven't been
        // downloaded yet will cause String(contentsOf:) to block the main
        // thread while the file downloads. Detect that case upfront and
        // trigger an async download instead of hanging.
        if let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey
        ]), values.isUbiquitousItem == true {
            if values.ubiquitousItemIsDownloading == true {
                loadError = "\"\(url.lastPathComponent)\" is downloading. Please try again shortly."
                sidebarSelection = activeFileURL
                return
            }
            if values.ubiquitousItemDownloadingStatus != .current {
                do {
                    try FileManager.default.startDownloadingUbiquitousItem(at: url)
                    loadError = "Downloading \"\(url.lastPathComponent)\"… Please try again shortly."
                } catch {
                    loadError = "Couldn't download \(url.lastPathComponent): \(error.localizedDescription)"
                }
                sidebarSelection = activeFileURL
                return
            }
        }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            openFiles.append(OpenFile(url: url, text: content, diskText: content))
            activeFileURL = url
            fileWatcher.watch(url)
        } catch {
            loadError = "Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"
            sidebarSelection = activeFileURL
        }
    }

    // MARK: - Close

    private func closeActiveTab() {
        guard let activeFileURL else { return }
        requestClose(activeFileURL)
    }

    private func requestClose(_ url: URL) {
        guard let file = openFiles.first(where: { $0.url == url }) else { return }
        if file.isDirty {
            pendingClose = url
            return
        }
        performClose(url)
    }

    private func performClose(_ url: URL) {
        guard let idx = openFiles.firstIndex(where: { $0.url == url }) else { return }
        openFiles.remove(at: idx)
        fileWatcher.unwatch(url)

        if activeFileURL == url {
            if openFiles.isEmpty {
                activeFileURL = nil
                sidebarSelection = nil
            } else {
                let nextIdx = min(idx, openFiles.count - 1)
                let nextURL = openFiles[nextIdx].url
                activeFileURL = nextURL
                sidebarSelection = nextURL
            }
        }
    }

    // MARK: - Create file / folder

    private func performCreate(_ request: CreateRequest) {
        let trimmed = newEntryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Reject path separators so users can't traverse out of the workspace
        // by typing "../foo" in the prompt.
        guard !trimmed.contains("/"), !trimmed.contains(":") else {
            loadError = "Names can't contain '/' or ':'."
            return
        }

        let target = request.directory.appendingPathComponent(trimmed)
        let fm = FileManager.default

        guard !fm.fileExists(atPath: target.path) else {
            loadError = "\(trimmed) already exists."
            return
        }

        do {
            switch request.kind {
            case .folder:
                try fm.createDirectory(at: target, withIntermediateDirectories: false)
            case .file:
                try Data().write(to: target)
            }
        } catch {
            loadError = "Couldn't create \(trimmed): \(error.localizedDescription)"
            return
        }

        // Force the sidebar to re-read so the new entry appears immediately.
        sidebarRefreshToken = UUID()

        if request.kind == .file {
            openTab(for: target)
        }
    }

    // MARK: - Rename

    private func performRename() {
        guard let renameTarget else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !trimmed.contains("/"), !trimmed.contains(":") else {
            loadError = "Names can't contain '/' or ':'."
            return
        }

        let folder = renameTarget.deletingLastPathComponent()
        let newURL = folder.appendingPathComponent(trimmed)
        guard newURL != renameTarget else { return }

        let fm = FileManager.default
        guard !fm.fileExists(atPath: newURL.path) else {
            loadError = "\(trimmed) already exists."
            return
        }

        do {
            try fm.moveItem(at: renameTarget, to: newURL)
            fileWatcher.unwatch(renameTarget)
            fileWatcher.watch(newURL)
            updateOpenFileURLs(from: renameTarget, to: newURL)
            sidebarRefreshToken = UUID()
        } catch {
            loadError = "Couldn't rename: \(error.localizedDescription)"
        }
    }

    // MARK: - Trash

    private func trashConfirmationMessage(for urls: [URL]) -> String {
        if urls.count == 1 {
            let hasDirty = openFiles.contains { $0.isDirty && ($0.url == urls[0] || $0.url.path.hasPrefix(urls[0].path + "/")) }
            let base = "Are you sure you want to move \(urls[0].lastPathComponent) to the Trash?"
            return hasDirty ? base + " Unsaved changes will be lost." : base
        }
        return "Are you sure you want to move \(urls.count) items to the Trash?"
    }

    private func performTrash(_ urls: [URL]) {
        let fm = FileManager.default
        for url in urls {
            closeTrashedTabs(under: url)
            do {
                try fm.trashItem(at: url, resultingItemURL: nil)
            } catch {
                loadError = "Couldn't move \(url.lastPathComponent) to Trash: \(error.localizedDescription)"
            }
        }
        sidebarRefreshToken = UUID()
    }

    private func closeTrashedTabs(under url: URL) {
        let toClose = openFiles.filter { $0.url == url || $0.url.path.hasPrefix(url.path + "/") }
        for file in toClose.reversed() {
            guard let idx = openFiles.firstIndex(where: { $0.url == file.url }) else { continue }
            openFiles.remove(at: idx)
            fileWatcher.unwatch(file.url)
        }
        if let active = activeFileURL {
            if active == url || active.path.hasPrefix(url.path + "/") {
                if openFiles.isEmpty {
                    activeFileURL = nil
                    sidebarSelection = nil
                } else {
                    activeFileURL = openFiles[0].url
                    sidebarSelection = openFiles[0].url
                }
            }
        }
    }

    // MARK: - Duplicate

    private func performDuplicate(_ url: URL) {
        let folder = url.deletingLastPathComponent()
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let fm = FileManager.default

        var newName = ext.isEmpty ? "\(name) copy" : "\(name) copy.\(ext)"
        var dest = folder.appendingPathComponent(newName)
        var counter = 2
        while fm.fileExists(atPath: dest.path) {
            newName = ext.isEmpty ? "\(name) copy \(counter)" : "\(name) copy \(counter).\(ext)"
            dest = folder.appendingPathComponent(newName)
            counter += 1
        }

        do {
            try fm.copyItem(at: url, to: dest)
            sidebarRefreshToken = UUID()
        } catch {
            loadError = "Couldn't duplicate \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    // MARK: - Move / Copy (drag-and-drop)

    private func performMove(sources: [URL], destFolder: URL) {
        let fm = FileManager.default

        let validSources = sources.filter { source in
            source != destFolder
            && !destFolder.path.hasPrefix(source.path + "/")
            && source.deletingLastPathComponent() != destFolder
            && fm.fileExists(atPath: source.path)
        }
        guard !validSources.isEmpty else { return }

        for source in validSources {
            let dest = destFolder.appendingPathComponent(source.lastPathComponent)
            if fm.fileExists(atPath: dest.path) {
                loadError = "\(source.lastPathComponent) already exists in \(destFolder.lastPathComponent)."
                return
            }
        }

        for source in validSources {
            let dest = destFolder.appendingPathComponent(source.lastPathComponent)
            let isInternal = source.path.hasPrefix(folderURL.path)

            do {
                if isInternal {
                    try fm.moveItem(at: source, to: dest)
                    updateOpenFileURLs(from: source, to: dest)
                } else {
                    try fm.copyItem(at: source, to: dest)
                }
            } catch {
                loadError = "Couldn't \(isInternal ? "move" : "copy") \(source.lastPathComponent): \(error.localizedDescription)"
                break
            }
        }

        sidebarRefreshToken = UUID()
    }

    private func updateOpenFileURLs(from oldBase: URL, to newBase: URL) {
        for i in openFiles.indices {
            if openFiles[i].url == oldBase {
                openFiles[i] = OpenFile(url: newBase, text: openFiles[i].text, diskText: openFiles[i].diskText)
            } else if openFiles[i].url.path.hasPrefix(oldBase.path + "/") {
                let relative = String(openFiles[i].url.path.dropFirst(oldBase.path.count))
                let newURL = URL(fileURLWithPath: newBase.path + relative)
                openFiles[i] = OpenFile(url: newURL, text: openFiles[i].text, diskText: openFiles[i].diskText)
            }
        }
        if let active = activeFileURL {
            if active == oldBase {
                activeFileURL = newBase
            } else if active.path.hasPrefix(oldBase.path + "/") {
                let relative = String(active.path.dropFirst(oldBase.path.count))
                activeFileURL = URL(fileURLWithPath: newBase.path + relative)
            }
        }
        sidebarSelection = activeFileURL
    }

    // MARK: - Save

    private func save(url: URL? = nil) {
        let target = url ?? activeFileURL
        guard let target,
              let idx = openFiles.firstIndex(where: { $0.url == target }) else { return }
        do {
            try openFiles[idx].text.write(to: target, atomically: true, encoding: .utf8)
            openFiles[idx].diskText = openFiles[idx].text
        } catch {
            loadError = "Couldn't save \(target.lastPathComponent): \(error.localizedDescription)"
        }
    }

    // MARK: - Sandbox

    private func startAccess() {
        didStartAccess = folderURL.startAccessingSecurityScopedResource()
    }

    private func stopAccess() {
        if didStartAccess {
            folderURL.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - Scroll sync (mirrors ContentViewDocument)

    private func wireScrollSync() {
        guard scrollSyncCancellables.isEmpty else { return }

        scrollSync.editorScrolled
            .throttle(for: .milliseconds(16), scheduler: RunLoop.main, latest: true)
            .sink { [scrollSync] line in
                guard !scrollSync.isSyncing else { return }
                scrollSync.isSyncing = true
                scrollSync.scrollPreviewToLine?(line)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    scrollSync.isSyncing = false
                }
            }
            .store(in: &scrollSyncCancellables)

        scrollSync.previewScrolled
            .throttle(for: .milliseconds(16), scheduler: RunLoop.main, latest: true)
            .sink { [scrollSync] line in
                guard !scrollSync.isSyncing else { return }
                scrollSync.isSyncing = true
                scrollSync.scrollEditorToLine?(line)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    scrollSync.isSyncing = false
                }
            }
            .store(in: &scrollSyncCancellables)
    }

    // MARK: - External file changes

    private func wireFileWatcher() {
        fileWatcher.onFileChanged = { url in
            reloadFromDisk(url)
        }
    }

    private func reloadFromDisk(_ url: URL) {
        guard let idx = openFiles.firstIndex(where: { $0.url == url }) else { return }
        guard !openFiles[idx].isDirty else { return }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            openFiles[idx].text = content
            openFiles[idx].diskText = content
        } catch {
            // File may have been deleted or is temporarily unavailable.
        }
    }
}

// MARK: - Create request

struct CreateRequest: Identifiable, Equatable {
    let directory: URL
    let kind: FolderSidebar.CreateKind

    var id: String { directory.path + "|" + (kind == .file ? "f" : "d") }
}

// MARK: - Tab model

struct OpenFile: Identifiable, Equatable {
    let url: URL
    var text: String
    var diskText: String

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var isDirty: Bool { text != diskText }
}

// MARK: - Tab strip

private struct TabStrip: View {
    let files: [OpenFile]
    let activeURL: URL?
    let onSelect: (URL) -> Void
    let onClose: (URL) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(files) { file in
                    TabItem(
                        file: file,
                        isActive: file.url == activeURL,
                        onSelect: { onSelect(file.url) },
                        onClose: { onClose(file.url) }
                    )
                    Divider().frame(height: 22)
                }
            }
        }
        .frame(height: 32)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
    }
}

private struct TabItem: View {
    let file: OpenFile
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text(file.name)
                .lineLimit(1)
                .font(.system(size: 12))
                .foregroundStyle(isActive ? .primary : .secondary)

            ZStack {
                if file.isDirty && !isHovering {
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 7, height: 7)
                } else {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovering || isActive ? 1 : 0)
                }
            }
            .frame(width: 14, height: 14)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(isActive ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { onSelect() }
    }
}

// MARK: - Save / close focused values

struct FolderSaveAction: Equatable {
    let canSave: Bool
    let perform: () -> Void

    static func == (lhs: FolderSaveAction, rhs: FolderSaveAction) -> Bool {
        lhs.canSave == rhs.canSave
    }
}

private struct FolderSaveActionKey: FocusedValueKey {
    typealias Value = FolderSaveAction
}

extension FocusedValues {
    var folderSave: FolderSaveAction? {
        get { self[FolderSaveActionKey.self] }
        set { self[FolderSaveActionKey.self] = newValue }
    }
}

struct FolderCloseTabAction: Equatable {
    let canClose: Bool
    let perform: () -> Void

    static func == (lhs: FolderCloseTabAction, rhs: FolderCloseTabAction) -> Bool {
        lhs.canClose == rhs.canClose
    }
}

private struct FolderCloseTabActionKey: FocusedValueKey {
    typealias Value = FolderCloseTabAction
}

extension FocusedValues {
    var folderCloseTab: FolderCloseTabAction? {
        get { self[FolderCloseTabActionKey.self] }
        set { self[FolderCloseTabActionKey.self] = newValue }
    }
}
