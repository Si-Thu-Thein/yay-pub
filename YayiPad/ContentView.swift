import SwiftUI
import YayCore
import YayPreview
import YayTextEditor

struct ContentView: View {
    @Binding var document: MarkdownFileDocument
    let fileURL: URL?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var configuration: YayEditorConfiguration = .standard
    @StateObject private var scrollSync = ScrollSyncBridge()
    @StateObject private var finder = IOSTextFinder()
    @State private var showsPreview: Bool = true
    @State private var showsFindBar: Bool = false
    @State private var hasSecurityScope: Bool = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            toggleFindBar()
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .keyboardShortcut("f", modifiers: .command)
                        .accessibilityLabel(showsFindBar ? "Hide find bar" : "Find")
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showsPreview.toggle()
                        } label: {
                            Image(systemName: showsPreview ? "eye.slash" : "eye")
                        }
                        .accessibilityLabel(showsPreview ? "Hide preview" : "Show preview")
                        .disabled(!isPreviewSupported)
                    }
                }
        }
        .onAppear {
            // The URL vended by DocumentGroup / UIDocumentBrowserViewController is
            // security-scoped. Without claiming the scope, sibling-file reads from
            // the preview's LocalFileSchemeHandler (e.g. relative <img> sources)
            // silently fail on device when the document lives outside the app
            // sandbox (iCloud Drive, Files-app providers, etc.). Held for the
            // lifetime of the open document.
            if let fileURL, fileURL.startAccessingSecurityScopedResource() {
                hasSecurityScope = true
            }
        }
        .onDisappear {
            if hasSecurityScope, let fileURL {
                fileURL.stopAccessingSecurityScopedResource()
                hasSecurityScope = false
            }
            finder.detach()
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            if showsFindBar {
                FindBarView(finder: finder) {
                    closeFindBar()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            mainPane
        }
        .animation(.easeInOut(duration: 0.18), value: showsFindBar)
    }

    @ViewBuilder
    private var mainPane: some View {
        // Always show the editor as the primary column. In regular-width iPad,
        // also show the preview side-by-side when the toggle is on. In compact
        // width (Slide Over, narrow split-view), the preview is hidden so the
        // editor remains usable as a text editor — that's the load-bearing
        // function of this app and must never be unreachable.
        if isPreviewSupported && showsPreview {
            HStack(spacing: 0) {
                editor
                Divider()
                preview
                    .frame(maxWidth: .infinity)
            }
        } else {
            editor
        }
    }

    private var isPreviewSupported: Bool {
        horizontalSizeClass == .regular
    }

    private var editor: some View {
        YayTextEditor(
            text: $document.text,
            configuration: configuration,
            scrollSync: scrollSync,
            finder: finder
        )
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .bottom)
    }

    private var preview: some View {
        MarkdownPreviewView(
            markdown: document.text,
            theme: configuration.theme,
            baseURL: fileURL?.deletingLastPathComponent(),
            scrollSync: scrollSync
        )
    }

    private var navigationTitle: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
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
        // Clearing findString triggers the finder's debounced clearHighlights
        // path. Don't detach — the editor's UIViewRepresentable holds a
        // reference and updateUIView will re-attach on the next open, but
        // skipping the detach lets the finder stay primed if the user reopens.
        finder.findString = ""
    }
}
