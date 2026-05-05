//
//  YayApp.swift
//  Yay
//
//  Created by Saturngod on 8/27/25.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import YayExport
import YayPreview
import YayTextEditor

/// NSDocument-based app delegate. macOS handles document window restoration
/// natively via `autosavesInPlace` + `encodeRestorableState`. We only need to
/// route folder URLs to `FolderWindowManager` and persist folder workspace
/// state ourselves.
final class YayAppDelegate: NSObject, NSApplicationDelegate {
    private static let openFolderURLsKey = "restorableFolderURLs"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Restore previously open folder workspaces.
        DispatchQueue.main.async {
            let folderPaths = UserDefaults.standard.stringArray(forKey: Self.openFolderURLsKey) ?? []
            for path in folderPaths where FileManager.default.fileExists(atPath: path) {
                FolderWindowManager.shared.open(URL(fileURLWithPath: path), addToRecent: false)
            }

            // If no documents were restored, create an empty one (like Cmd+N).
            if NSDocumentController.shared.documents.isEmpty {
                self.createNewDocument()
            }
        }
    }

    func application(_ sender: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.hasDirectoryPath {
                FolderWindowManager.shared.open(url)
            } else {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            }
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        createNewDocument()
        return false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            createNewDocument()
            return false
        }
        return true
    }

    @discardableResult
    private func createNewDocument() -> MarkdownDocument {
        let doc = MarkdownDocument()
        NSDocumentController.shared.addDocument(doc)
        doc.makeWindowControllers()
        doc.showWindows()
        NSApp.activate(ignoringOtherApps: true)
        return doc
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let fm = FileManager.default
        let folderURLs = FolderWindowManager.shared.openFolderURLs.filter {
            fm.fileExists(atPath: $0.path)
        }
        UserDefaults.standard.set(folderURLs.map(\.path), forKey: Self.openFolderURLsKey)
        return .terminateNow
    }
}

@main
struct YayApp: App {
    @NSApplicationDelegateAdaptor(YayAppDelegate.self) private var appDelegate

    init() {
        NSWindow.allowsAutomaticWindowTabbing = true
        UserDefaults.standard.set("manual", forKey: "AppleWindowTabbingMode")
        UserDefaults.standard.set(true, forKey: "NSQuitAlwaysKeepsWindows")
        UserDefaults.standard.register(defaults: [
            "editorFontFamily": "Menlo",
            "editorFontSize": 14.0,
            "editorLineHeight": 1.5,
        ])
    }

    var body: some Scene {
        Settings {
            TabView {
                GeneralSettingsPane()
                    .tabItem {
                        Label("General", systemImage: "gear")
                    }
                EditorSettingsPane()
                    .tabItem {
                        Label("Editor", systemImage: "textformat")
                    }
                PreviewSettingsPane()
                    .tabItem {
                        Label("Preview", systemImage: "eye")
                    }
                PDFSettingsPane()
                    .tabItem {
                        Label("PDF", systemImage: "doc.richtext")
                    }
            }
            .frame(width: 500, height: 420)
        }
        .commands {
            ExportCommands()
            FolderCommands()
            FindCommands()

            CommandGroup(replacing: .newItem) {
                Button("New") {
                    let doc = MarkdownDocument()
                    NSDocumentController.shared.addDocument(doc)
                    doc.makeWindowControllers()
                    doc.showWindows()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Open…") {
                    NSDocumentController.shared.openDocument(nil)
                }
                .keyboardShortcut("o", modifiers: .command)

                OpenFolderButton()
                OpenRecentMenu()
                Divider()

                Button("New Tab") {
                    guard let frontWindow = NSApp.keyWindow ?? NSApp.mainWindow else {
                        let doc = MarkdownDocument()
                        NSDocumentController.shared.addDocument(doc)
                        doc.makeWindowControllers()
                        doc.showWindows()
                        return
                    }
                    let doc = MarkdownDocument()
                    NSDocumentController.shared.addDocument(doc)
                    doc.makeWindowControllers()
                    guard let newWindow = doc.windowControllers.first?.window else { return }
                    frontWindow.addTabbedWindow(newWindow, ordered: .above)
                    newWindow.makeKeyAndOrderFront(nil)
                }
                .keyboardShortcut("t", modifiers: .command)
            }

            CommandGroup(after: .toolbar) {
                Button("Toggle Sidebar") {
                    NSApp.sendAction(
                        #selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .control])

                Divider()

                Menu("Preview") {
                    Button("Toggle Preview") {
                        NotificationCenter.default.post(name: .togglePreview, object: nil)
                    }
                    .keyboardShortcut("r", modifiers: .command)

                    Divider()

                    Button("Split") {
                        NotificationCenter.default.post(name: .setPreviewModeSplit, object: nil)
                    }
                    .keyboardShortcut("1", modifiers: [.command, .shift])

                    Button("Full") {
                        NotificationCenter.default.post(name: .setPreviewModeFull, object: nil)
                    }
                    .keyboardShortcut("2", modifiers: [.command, .shift])
                }
            }
        }
    }
}

struct FindCommands: Commands {
    var body: some Commands {
        CommandMenu("Find") {
            Button("Find…") {
                FindPanelController.shared.showPanel()
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("Find Next") {
                FindPanelController.shared.performFindNext()
            }
            .keyboardShortcut("g", modifiers: .command)

            Button("Find Previous") {
                FindPanelController.shared.performFindPrevious()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
        }
    }
}

// MARK: - Export

@MainActor
struct ExportCommands: Commands {
    @FocusedValue(\.markdownExport) private var focusedExportContext: MarkdownExportContext?
    @ObservedObject private var exportRegistry = WindowExportContextRegistry.shared

    private var exportContext: MarkdownExportContext? {
        focusedExportContext ?? exportRegistry.currentContext()
    }

    /// HTML export writes the preview document directly.
    private static let renderer = MarkdownRenderer()

    /// Scroll-sync sentinels are editor-only metadata and should not appear in
    /// exported artifacts.
    private static let sentinelRegex = try! NSRegularExpression(
        pattern: "<!--SLINE:\\d+-->\\n?"
    )

    private static var pdfExporter: MarkdownPDFExporter?

    var body: some Commands {
        CommandGroup(before: .printItem) {
            Menu("Export") {
                Button("HTML…") {
                    if let exportContext {
                        ExportCommands.exportHTML(exportContext)
                    }
                }
                .disabled(exportContext == nil)
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("PDF…") {
                    if let exportContext {
                        ExportCommands.exportPDF(exportContext)
                    }
                }
                .disabled(exportContext == nil)
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }
    }

    static func exportHTML(_ context: MarkdownExportContext) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = context.suggestedFilename
        panel.canCreateDirectories = true
        panel.title = "Export HTML"

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        var html = renderer.render(context.text)
        html = sentinelRegex.stringByReplacingMatches(
            in: html,
            range: NSRange(location: 0, length: (html as NSString).length),
            withTemplate: ""
        )

        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Export Failed"
            alert.runModal()
        }
    }

    static func exportPDF(_ context: MarkdownExportContext) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = context.suggestedFilename
            .replacingOccurrences(of: ".html", with: ".pdf")
        panel.canCreateDirectories = true
        panel.title = "Export PDF"

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        let displayName = context.suggestedFilename
            .replacingOccurrences(of: ".html", with: "")
        let defaults = UserDefaults.standard
        let paperSizeID = defaults.string(forKey: "pdfPaperSize") ?? PDFPaperSize.a4ID
        let pageSize = PDFPaperSize.size(for: paperSizeID)
        let pdfFontSize = defaults.object(forKey: "pdfFontSize") == nil ? 11 : defaults.double(forKey: "pdfFontSize")
        let pdfLineHeight = defaults.object(forKey: "pdfLineHeight") == nil ? 1.65 : defaults.double(forKey: "pdfLineHeight")
        let exporter = MarkdownPDFExporter(
            headerText: defaults.string(forKey: "pdfHeaderText") ?? "",
            headerAlign: defaults.integer(forKey: "pdfHeaderAlign"),
            footerText: defaults.string(forKey: "pdfFooterText") ?? "",
            footerAlign: defaults.integer(forKey: "pdfFooterAlign"),
            fileName: displayName,
            pdfFontFamily: defaults.string(forKey: "pdfFontFamily") ?? "Georgia",
            pdfFontSize: CGFloat(pdfFontSize),
            pdfLineHeight: CGFloat(pdfLineHeight)
        )
        Self.pdfExporter = exporter

        exporter.export(
            markdown: context.text,
            to: url,
            baseURL: context.fileURL?.deletingLastPathComponent(),
            pageSize: pageSize
        ) { result in
            Self.pdfExporter = nil
            if case .failure(let error) = result {
                let alert = NSAlert()
                alert.messageText = "PDF Export Failed"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }
}

// MARK: - Folder workspace

@MainActor
final class FolderWindowManager {
    static let shared = FolderWindowManager()
    private(set) var windows: [NSWindow] = []

    var openFolderURLs: [URL] {
        windows.compactMap { $0.representedURL?.standardized }
    }

    func open(_ url: URL, addToRecent: Bool = true) {
        let canonical = url.standardized
        if let existing = windows.first(where: { $0.representedURL?.standardized == canonical }) {
            existing.makeKeyAndOrderFront(nil)
            if addToRecent {
                RecentDocumentsMenuModel.shared.noteOpened(canonical)
            }
            return
        }
        let controller = NSHostingController(rootView: FolderWorkspaceView(folderURL: canonical))
        let window = NSWindow(contentViewController: controller)
        window.representedURL = canonical
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        let autosaveName = "YayFolder-" + String(canonical.path.hashValue)
        window.setFrameAutosaveName(autosaveName)
        window.setContentSize(NSSize(width: 1100, height: 720))
        window.center()

        window.makeKeyAndOrderFront(nil)
        windows.append(window)
        if addToRecent {
            RecentDocumentsMenuModel.shared.noteOpened(canonical)
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self, weak window] _ in
            Task { @MainActor in
                guard let self, let window else { return }
                self.windows.removeAll { $0 === window }
            }
        }
    }
}

struct OpenFolderButton: View {
    var body: some View {
        Button("Open Folder…") {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.title = "Open Folder"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            FolderWindowManager.shared.open(url)
        }
        .keyboardShortcut("o", modifiers: [.command, .shift])
    }
}

/// Adds a Save command that fires when a folder workspace window is focused.
/// `.replacing(.saveItem)` would clobber the standard document Save, so we
/// add ours alongside; the `.disabled` binding gates the shortcut to fire
/// only when the focused window has a dirty file to save.
struct FolderCommands: Commands {
    @FocusedValue(\.folderSave) private var folderSave
    @FocusedValue(\.folderCloseTab) private var folderCloseTab

    var body: some Commands {
        // Replace the built-in Save so we own the ⌘S shortcut. If a folder
        // window is focused we call our save action; otherwise we forward
        // `saveDocument:` up the responder chain so DocumentGroup-backed
        // windows still save normally.
        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                if let folderSave {
                    folderSave.perform()
                } else {
                    NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: nil)
                }
            }
            .keyboardShortcut("s", modifiers: .command)

            Button("Save As…") {
                NSApp.sendAction(#selector(NSDocument.saveAs(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(folderSave != nil)  // No save-as for folder workspaces yet
        }

        // Cmd+W closes the active folder tab or the active document window/tab.
        // A disabled SwiftUI shortcut still captures the key event, so we must
        // never disable this — instead always route to the right action.
        CommandGroup(after: .windowList) {
            Button("Close Tab") {
                if let folderCloseTab, folderCloseTab.canClose {
                    folderCloseTab.perform()
                } else {
                    NSApp.sendAction(#selector(NSWindow.performClose(_:)), to: nil, from: nil)
                }
            }
            .keyboardShortcut("w", modifiers: .command)
        }
    }
}
