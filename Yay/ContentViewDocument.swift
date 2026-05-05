import SwiftUI
import Combine
import YayCore
import YayExport
import YayTextEditor
import YayPreview

enum PreviewMode: String, CaseIterable {
    case split = "Split"
    case full = "Full"
}

struct ContentViewDocument: View {
    @ObservedObject var document: MarkdownDocument

    @AppStorage("editorFontFamily") private var fontFamily = "Menlo"
    @AppStorage("editorFontSize") private var fontSize: Double = 14
    @AppStorage("editorLineHeight") private var lineHeight: Double = 1.5

    @State private var showPreview = false
    @State private var previewMode: PreviewMode = .split
    @State private var splitRatio: CGFloat = 0.5
    @StateObject private var scrollSync = ScrollSyncBridge()
    @State private var scrollSyncCancellables: Set<AnyCancellable> = []
    private var textBinding: Binding<String> {
        Binding(
            get: { document.text },
            set: { document.text = $0 }
        )
    }

    private var fileURL: URL? { document.fileURL }

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

    private var baseURL: URL? {
        fileURL?.deletingLastPathComponent()
    }

    var body: some View {
        GeometryReader { geo in
            if showPreview && previewMode == .split {
                let dividerX = geo.size.width * splitRatio

                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        YayTextEditor(text: textBinding, configuration: editorConfiguration, scrollSync: scrollSync)
                            .frame(width: dividerX)

                        MarkdownPreviewView(
                            markdown: document.text,
                            baseURL: baseURL,
                            scrollSync: scrollSync
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    SplitDivider()
                        .frame(height: geo.size.height)
                        .offset(x: dividerX - 6)
                        .gesture(
                            DragGesture(minimumDistance: 1, coordinateSpace: .named("splitContainer"))
                                .onChanged { value in
                                    let ratio = value.location.x / geo.size.width
                                    splitRatio = min(max(ratio, 0.2), 0.8)
                                }
                        )
                }
                .coordinateSpace(name: "splitContainer")
            } else if showPreview {
                MarkdownPreviewView(
                    markdown: document.text,
                    baseURL: baseURL,
                    scrollSync: scrollSync
                )
            } else {
                YayTextEditor(text: textBinding, configuration: editorConfiguration)
            }
        }
        .focusedSceneValue(\.markdownExport, MarkdownExportContext(
            text: document.text,
            suggestedFilename: (document.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled") + ".html",
            fileURL: document.fileURL
        ))
        .background(
            WindowExportContextWriter(context: MarkdownExportContext(
                text: document.text,
                suggestedFilename: (document.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled") + ".html",
                fileURL: document.fileURL
            ))
        )
        .onAppear {
            wireScrollSync()
        }
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
    }

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
}

struct SplitDivider: View {
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Color.clear
                .frame(width: 12)
                .contentShape(Rectangle())

            Rectangle()
                .fill(Color.gray.opacity(isHovering ? 0.4 : 0.2))
                .frame(width: 1)

            if isHovering {
                VStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(Color.gray.opacity(0.6))
                            .frame(width: 4, height: 4)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

extension Notification.Name {
    static let togglePreview = Notification.Name("togglePreview")
    static let setPreviewModeSplit = Notification.Name("setPreviewModeSplit")
    static let setPreviewModeFull = Notification.Name("setPreviewModeFull")
}

#Preview {
    let doc = MarkdownDocument()
    doc.text = "# Title\n\nHello **world**"
    return ContentViewDocument(document: doc)
}
