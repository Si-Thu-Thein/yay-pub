import SwiftUI

struct FolderSidebar: View {
    let rootURL: URL
    @Binding var selection: URL?
    var onCreate: (URL, CreateKind) -> Void = { _, _ in }
    var onRename: (URL) -> Void = { _ in }
    var onTrash: ([URL]) -> Void = { _ in }
    var onDuplicate: (URL) -> Void = { _ in }
    var onMove: ([URL], URL) -> Void = { _, _ in }
    var onReveal: (URL) -> Void = { _ in }

    enum CreateKind {
        case file, folder
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rootEntries()) { entry in
                    EntryNode(
                        entry: entry,
                        depth: 0,
                        selection: $selection,
                        onCreate: onCreate,
                        onRename: onRename,
                        onTrash: onTrash,
                        onDuplicate: onDuplicate,
                        onMove: onMove,
                        onReveal: onReveal
                    )
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .dropDestination(for: URL.self) { urls, _ in
            onMove(urls, rootURL)
            return true
        }
        .contextMenu {
            createButtons(in: rootURL)
        }
    }

    private func rootEntries() -> [FolderEntry] {
        FolderEntry(url: rootURL, isDirectory: true).children ?? []
    }

    @ViewBuilder
    private func createButtons(in directory: URL) -> some View {
        Button("New File…") { onCreate(directory, .file) }
        Button("New Folder…") { onCreate(directory, .folder) }
    }
}

private struct EntryNode: View {
    let entry: FolderEntry
    let depth: Int
    @Binding var selection: URL?
    let onCreate: (URL, FolderSidebar.CreateKind) -> Void
    let onRename: (URL) -> Void
    let onTrash: ([URL]) -> Void
    let onDuplicate: (URL) -> Void
    let onMove: ([URL], URL) -> Void
    let onReveal: (URL) -> Void

    @State private var isExpanded = false
    @State private var isDropTargeted = false

    private var leadingPadding: CGFloat { CGFloat(depth) * 16 + 8 }

    var body: some View {
        if entry.isDirectory {
            folderNode
        } else if entry.isOpenable {
            fileNode
        } else {
            disabledNode
        }
    }

    private var folderNode: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
                FolderRow(entry: entry)
                Spacer(minLength: 0)
            }
            .padding(.leading, leadingPadding)
            .padding(.trailing, 8)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            }
            .draggable(entry.url) {
                dragPreview
            }
            .dropDestination(for: URL.self) { urls, _ in
                onMove(urls, entry.url)
                return true
            }
            .background(
                isDropTargeted
                    ? Color.accentColor.opacity(0.2)
                    : Color.clear
            )
            .contextMenu {
                contextMenu(for: entry)
            }

            if isExpanded {
                ForEach(entry.children ?? []) { child in
                    EntryNode(
                        entry: child,
                        depth: depth + 1,
                        selection: $selection,
                        onCreate: onCreate,
                        onRename: onRename,
                        onTrash: onTrash,
                        onDuplicate: onDuplicate,
                        onMove: onMove,
                        onReveal: onReveal
                    )
                }
            }
        }
    }

    private var fileNode: some View {
        HStack(spacing: 4) {
            Spacer().frame(width: 10)
            FolderRow(entry: entry)
            Spacer(minLength: 0)
        }
        .padding(.leading, leadingPadding)
        .padding(.trailing, 8)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            selection = entry.url
        }
        .draggable(entry.url) {
            dragPreview
        }
        .background(
            selection == entry.url
                ? Color.accentColor.opacity(0.2)
                : Color.clear
        )
        .contextMenu {
            contextMenu(for: entry)
        }
    }

    private var disabledNode: some View {
        HStack(spacing: 4) {
            Spacer().frame(width: 10)
            FolderRow(entry: entry, disabled: true)
            Spacer(minLength: 0)
        }
        .padding(.leading, leadingPadding)
        .padding(.trailing, 8)
        .padding(.vertical, 3)
    }

    private var dragPreview: some View {
        Label(entry.name, systemImage: entry.isDirectory ? "folder" : "doc.text")
    }

    @ViewBuilder
    private func contextMenu(for entry: FolderEntry) -> some View {
        let target = entry.isDirectory ? entry.url : entry.url.deletingLastPathComponent()
        Button("New File…") { onCreate(target, .file) }
        Button("New Folder…") { onCreate(target, .folder) }
        Divider()
        Button("Rename…") { onRename(entry.url) }
        Button("Duplicate") { onDuplicate(entry.url) }
        Divider()
        Button("Move to Trash", role: .destructive) { onTrash([entry.url]) }
        Divider()
        Button("Reveal in Finder") { onReveal(entry.url) }
    }
}

private struct FolderRow: View {
    let entry: FolderEntry
    var disabled: Bool = false

    var body: some View {
        Label {
            Text(entry.name)
        } icon: {
            Image(systemName: entry.isDirectory ? "folder" : "doc.text")
                .foregroundStyle(entry.isDirectory ? .blue : .secondary)
        }
        .foregroundStyle(disabled ? .tertiary : .primary)
        .opacity(disabled ? 0.5 : 1)
    }
}
