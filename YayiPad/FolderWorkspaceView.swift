import SwiftUI
import YayCore
import YayPreview
import YayTextEditor

//
//  FolderWorkspaceView.swift
//  YayiPad (Phase 4 — iPad folder workspace)
//
//  Minimal iPad-flavored folder workspace. Compared to macOS:
//    - Single-file editing (no tabs).
//    - Flat file list (no nested directory navigation).
//    - No rename/trash/duplicate/move — read + edit + save only.
//
//  These omissions keep the first iPad cut tractable without ability to
//  verify UX on a real iPad. The macOS multi-tab/tree workspace can be
//  ported in a follow-up once the basic flow is validated.
//

struct FolderWorkspaceView: View {
    let folderURL: URL
    let onClose: () -> Void

    @State private var files: [URL] = []
    @State private var selectedFile: URL?
    @State private var fileText: String = ""
    @State private var diskText: String = ""
    @State private var configuration: YayEditorConfiguration = .standard
    @StateObject private var scrollSync = ScrollSyncBridge()
    @StateObject private var finder = IOSTextFinder()
    @State private var showsFindBar: Bool = false
    @State private var didStartAccess = false
    @State private var loadError: String?

    private var isDirty: Bool { fileText != diskText }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailColumn
        }
        .onAppear {
            didStartAccess = folderURL.startAccessingSecurityScopedResource()
            loadFiles()
        }
        .onDisappear {
            if didStartAccess {
                folderURL.stopAccessingSecurityScopedResource()
                didStartAccess = false
            }
            finder.detach()
        }
        .onChange(of: selectedFile) { _, new in
            loadFile(new)
        }
        .alert(
            "Couldn't open file",
            isPresented: Binding(
                get: { loadError != nil },
                set: { if !$0 { loadError = nil } }
            ),
            presenting: loadError
        ) { _ in
            Button("OK") { loadError = nil }
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(files, id: \.self, selection: $selectedFile) { url in
            Label(url.lastPathComponent, systemImage: "doc.text")
        }
        .listStyle(.sidebar)
        .navigationTitle(folderURL.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { onClose() }
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailColumn: some View {
        if let selectedFile {
            VStack(spacing: 0) {
                if showsFindBar {
                    FindBarView(finder: finder) {
                        closeFindBar()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                editorAndPreview(for: selectedFile)
            }
            .animation(.easeInOut(duration: 0.18), value: showsFindBar)
            .navigationTitle(selectedFile.lastPathComponent + (isDirty ? " • Edited" : ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        toggleFindBar()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .keyboardShortcut("f", modifiers: .command)
                    .accessibilityLabel(showsFindBar ? "Hide find bar" : "Find")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { saveFile() }
                        .disabled(!isDirty)
                        .keyboardShortcut("s", modifiers: .command)
                }
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 56))
                    .foregroundStyle(.tertiary)
                Text("Select a file")
                    .font(.title3)
                Text("Pick a Markdown file from the sidebar to start editing.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func editorAndPreview(for url: URL) -> some View {
        HStack(spacing: 0) {
            YayTextEditor(
                text: $fileText,
                configuration: configuration,
                scrollSync: scrollSync,
                finder: finder
            )
            .frame(maxWidth: .infinity)

            Divider()

            MarkdownPreviewView(
                markdown: fileText,
                theme: configuration.theme,
                baseURL: url.deletingLastPathComponent(),
                scrollSync: scrollSync
            )
            .frame(maxWidth: .infinity)
        }
        .id(url)  // Reset editor/preview state per selected file.
    }

    // MARK: - Find bar

    private func toggleFindBar() {
        if showsFindBar {
            closeFindBar()
        } else {
            showsFindBar = true
        }
    }

    private func closeFindBar() {
        showsFindBar = false
        finder.findString = ""
    }

    // MARK: - File IO

    private func loadFiles() {
        let fm = FileManager.default
        let urls: [URL]
        do {
            urls = try fm.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            loadError = "Couldn't read folder: \(error.localizedDescription)"
            return
        }

        let openable = urls.filter { url in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return !isDir
                && FolderEntry.openableExtensions.contains(url.pathExtension.lowercased())
        }
        files = openable.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent)
                == .orderedAscending
        }
    }

    private func loadFile(_ url: URL?) {
        guard let url else {
            fileText = ""
            diskText = ""
            return
        }
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            fileText = content
            diskText = content
        } catch {
            loadError = "Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"
            fileText = ""
            diskText = ""
        }
    }

    private func saveFile() {
        guard let selectedFile, isDirty else { return }
        do {
            try fileText.write(to: selectedFile, atomically: true, encoding: .utf8)
            diskText = fileText
        } catch {
            loadError = "Couldn't save \(selectedFile.lastPathComponent): \(error.localizedDescription)"
        }
    }
}
