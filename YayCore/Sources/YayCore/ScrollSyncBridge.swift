import Foundation
import Combine

/// Shared coordinator for line-anchored scroll sync between editor and preview.
///
/// Each view registers a `scrollToLine` handler during view construction and
/// publishes its own scroll position via `editorScrolled` / `previewScrolled`.
/// The owner (typically the document view) listens to those publishers and
/// drives the opposite side, gating with `isSyncing` to break feedback loops.
public final class ScrollSyncBridge: ObservableObject {
    public let editorScrolled = PassthroughSubject<Int, Never>()
    public let previewScrolled = PassthroughSubject<Int, Never>()

    public var scrollEditorToLine: ((Int) -> Void)?
    public var scrollPreviewToLine: ((Int) -> Void)?

    /// Set to true while a programmatic scroll is in flight so the receiving
    /// side can suppress its own scroll-driven publish.
    public var isSyncing: Bool = false

    public init() {}
}
