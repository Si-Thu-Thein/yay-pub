import Foundation

/// One row in the folder sidebar — either a directory (with lazily-loaded
/// children) or a leaf file. `OutlineGroup` walks the tree by reading
/// `children`; returning nil marks the row as a leaf so the disclosure
/// triangle doesn't show.
struct FolderEntry: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool

    var id: URL { url }
    var name: String { url.lastPathComponent }

    static let openableExtensions: Set<String> = [
        "md", "markdown", "mdown", "mkd", "mdx", "txt"
    ]

    var isOpenable: Bool {
        isDirectory || Self.openableExtensions.contains(url.pathExtension.lowercased())
    }

    /// Returns nil for files so OutlineGroup treats them as leaves.
    /// Returns [] for empty directories so the chevron still renders.
    var children: [FolderEntry]? {
        guard isDirectory else { return nil }
        let fm = FileManager.default
        let urls: [URL]
        do {
            urls = try fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }

        let entries: [FolderEntry] = urls.compactMap { childURL in
            let isDir = (try? childURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if !isDir { return nil }
            return FolderEntry(url: childURL, isDirectory: true)
        }
        + urls.compactMap { childURL in
            let isDir = (try? childURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir { return nil }
            return FolderEntry(url: childURL, isDirectory: false)
        }

        return entries.sorted { lhs, rhs in
            // Directories first, then case-insensitive name.
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
