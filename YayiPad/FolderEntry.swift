import Foundation

/// Lightweight model for a file or directory in a folder workspace. The iPad
/// folder workspace consumes only the `openableExtensions` constant for now;
/// the full tree-walking shape is kept so it can be reused if/when the iPad
/// workspace grows directory navigation.
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
}
