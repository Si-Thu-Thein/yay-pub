import AppKit
import SwiftUI

@MainActor
final class RecentDocumentsMenuModel: ObservableObject {
    static let shared = RecentDocumentsMenuModel()

    @Published private(set) var recentURLs: [URL] = []

    private let documentController = NSDocumentController.shared
    private var observers: [NSObjectProtocol] = []

    private init() {
        refresh()

        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                }
            }
        )
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func noteOpened(_ url: URL) {
        documentController.noteNewRecentDocumentURL(url.standardized)
        refresh()
    }

    func refresh() {
        recentURLs = documentController.recentDocumentURLs
    }

    func clear() {
        documentController.clearRecentDocuments(nil)
        refresh()
    }

    func open(_ url: URL) {
        let canonical = url.standardized
        guard FileManager.default.fileExists(atPath: canonical.path) else {
            presentMissingItemAlert(for: canonical)
            refresh()
            return
        }

        if isDirectory(canonical) {
            FolderWindowManager.shared.open(canonical)
            refresh()
            return
        }

        documentController.openDocument(withContentsOf: canonical, display: true) {
            [weak self] _, _, error in
            if let error {
                self?.documentController.presentError(error)
            }
            self?.refresh()
        }
    }

    func title(for url: URL) -> String {
        let name = url.lastPathComponent
        return name.isEmpty ? url.path : name
    }

    func subtitle(for url: URL) -> String {
        url.deletingLastPathComponent().path
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? url.hasDirectoryPath
    }

    private func presentMissingItemAlert(for url: URL) {
        let alert = NSAlert()
        alert.messageText = "Recent Item Not Found"
        alert.informativeText = "\(url.path) could not be opened because it no longer exists."
        alert.alertStyle = .warning
        alert.runModal()
    }
}

struct OpenRecentMenu: View {
    @ObservedObject private var model = RecentDocumentsMenuModel.shared

    var body: some View {
        Menu("Open Recent") {
            if model.recentURLs.isEmpty {
                Button("No Recent Documents") {}
                    .disabled(true)
            } else {
                ForEach(model.recentURLs, id: \.self) { url in
                    Button(model.title(for: url)) {
                        model.open(url)
                    }
                    .help(model.subtitle(for: url))
                }

                Divider()
            }

            Button("Clear Menu") {
                model.clear()
            }
            .disabled(model.recentURLs.isEmpty)
        }
        .onAppear {
            model.refresh()
        }
    }
}
