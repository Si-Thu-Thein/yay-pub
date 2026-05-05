#if os(macOS)
import AppKit
import SwiftUI
import YayCore

public struct YayTextEditor: NSViewRepresentable {
    @Binding var text: String
    public var configuration: YayEditorConfiguration = .standard
    public var scrollSync: ScrollSyncBridge?

    public init(
        text: Binding<String>,
        configuration: YayEditorConfiguration = .standard,
        scrollSync: ScrollSyncBridge? = nil
    ) {
        self._text = text
        self.configuration = configuration
        self.scrollSync = scrollSync
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()

        let textStorage = NSTextStorage()
        let layoutManager = MarkdownLayoutManager()
        let textContainer = NSTextContainer()
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = MarkdownNSTextView(frame: .zero, textContainer: textContainer)

        textView.string = text
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = true
        textView.font = configuration.theme.baseFont
        textView.textColor = configuration.theme.baseColor
        textView.delegate = context.coordinator

        layoutManager.lineHeightMultiple = configuration.lineHeightMultiple

        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)

        textContainer.lineFragmentPadding = configuration.lineFragmentPadding
        textView.textContainerInset = configuration.textContainerInset

        layoutManager.allowsNonContiguousLayout = true

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false

        if configuration.enablesLiveHighlighting {
            context.coordinator.performInitialHighlight(for: textView)
        }

        if configuration.enablesLiveHighlighting {
            context.coordinator.setupScrollObserver(for: scrollView, textView: textView)
        }

        context.coordinator.attach(
            scrollSync: scrollSync, scrollView: scrollView, textView: textView)

        FindPanelController.shared.attach(textView: textView)

        if configuration.focusOnAppear {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }

        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self

        context.coordinator.highlighter.updateConfiguration(configuration)

        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.attach(
            scrollSync: scrollSync, scrollView: scrollView, textView: textView)

        FindPanelController.shared.attach(textView: textView)

        if let lm = textView.layoutManager as? MarkdownLayoutManager {
            lm.lineHeightMultiple = configuration.lineHeightMultiple
        }

        let newFont = configuration.theme.baseFont
        if textView.font != newFont {
            textView.font = newFont
            textView.textColor = configuration.theme.baseColor
            if configuration.enablesLiveHighlighting {
                context.coordinator.highlighter.invalidateTree()
                context.coordinator.performInitialHighlight(for: textView)
            }
        }

        if textView.string != text {
            textView.string = text
            context.coordinator.invalidateLineIndex()
            if configuration.enablesLiveHighlighting {
                context.coordinator.highlighter.invalidateTree()
                context.coordinator.performInitialHighlight(for: textView)
            }
        }
    }

    public class Coordinator: NSObject, NSTextViewDelegate {
        var parent: YayTextEditor
        let highlighter: TreeSitterHighlighter
        private var pendingIncrementalWork: DispatchWorkItem?
        private var pendingFullWork: DispatchWorkItem?
        private var pendingScrollWork: DispatchWorkItem?
        private var pendingInitialWork: DispatchWorkItem?
        private var scrollObserver: NSObjectProtocol?
        private var syncScrollObserver: NSObjectProtocol?

        private let incrementalDebounce: TimeInterval = 0.05
        private let fullDebounce: TimeInterval = 0.5
        private let scrollDebounce: TimeInterval = 0.05

        private weak var scrollSync: ScrollSyncBridge?
        private weak var syncScrollView: NSScrollView?
        private weak var syncTextView: NSTextView?
        private var muteScrollPublishUntil: Date?

        private var lastHighlightedVisibleRange: NSRange?
        private var lineStarts: [Int] = [0]
        private var lineIndexTextLength = 0
        private var lineIndexDirty = true

        init(_ parent: YayTextEditor) {
            self.parent = parent
            self.highlighter = TreeSitterHighlighter(configuration: parent.configuration)
        }

        deinit {
            pendingIncrementalWork?.cancel()
            pendingFullWork?.cancel()
            pendingScrollWork?.cancel()
            pendingInitialWork?.cancel()
            if let observer = scrollObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = syncScrollObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        // MARK: - Scroll Sync Bridge

        func attach(scrollSync: ScrollSyncBridge?, scrollView: NSScrollView, textView: NSTextView) {
            syncScrollView = scrollView
            syncTextView = textView

            guard let scrollSync, scrollSync !== self.scrollSync else {
                self.scrollSync = scrollSync
                return
            }
            self.scrollSync = scrollSync

            scrollSync.scrollEditorToLine = { [weak self] line in
                self?.scrollEditor(toSourceLine: line)
            }

            scrollView.contentView.postsBoundsChangedNotifications = true
            if let existing = syncScrollObserver {
                NotificationCenter.default.removeObserver(existing)
            }
            syncScrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.publishScrollLine()
            }
        }

        private func publishScrollLine() {
            guard let scrollSync, !scrollSync.isSyncing else { return }
            if let mute = muteScrollPublishUntil, Date() < mute { return }
            guard let textView = syncTextView,
                let line = topVisibleSourceLine(in: textView)
            else { return }
            scrollSync.editorScrolled.send(line)
        }

        private func topVisibleSourceLine(in textView: NSTextView) -> Int? {
            guard let layoutManager = textView.layoutManager,
                let textContainer = textView.textContainer,
                let clipView = textView.enclosingScrollView?.contentView
            else { return nil }

            let visibleRect = clipView.documentVisibleRect
            let glyphRange = layoutManager.glyphRange(
                forBoundingRect: visibleRect, in: textContainer)
            guard glyphRange.length > 0 else { return 1 }
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphRange.location)

            let nsString = textView.string as NSString
            guard charIndex <= nsString.length else { return nil }

            return sourceLineNumber(for: charIndex, in: nsString)
        }

        private func scrollEditor(toSourceLine line: Int) {
            guard let textView = syncTextView,
                let scrollView = syncScrollView,
                let layoutManager = textView.layoutManager,
                textView.textContainer != nil
            else { return }

            let nsString = textView.string as NSString
            let length = nsString.length
            guard length > 0 else { return }

            let charIndex = characterIndex(forSourceLine: line, in: nsString)

            let glyphIndex = layoutManager.glyphIndexForCharacter(at: min(charIndex, length))
            layoutManager.ensureLayout(forGlyphRange: NSRange(location: glyphIndex, length: 0))
            let rect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)

            let inset = textView.textContainerInset
            let targetY = max(0, rect.origin.y + inset.height)

            muteScrollPublishUntil = Date().addingTimeInterval(0.25)

            let clip = scrollView.contentView
            let clamped = NSPoint(
                x: 0, y: min(targetY, max(0, (textView.frame.height) - clip.bounds.height)))
            clip.setBoundsOrigin(clamped)
            scrollView.reflectScrolledClipView(clip)
        }

        // MARK: - Visible Range

        func visibleCharacterRange(in textView: NSTextView, buffer: Int = 500) -> NSRange {
            guard let layoutManager = textView.layoutManager,
                let textContainer = textView.textContainer,
                let clipView = textView.enclosingScrollView?.contentView
            else {
                let length = (textView.string as NSString).length
                return NSRange(location: 0, length: length)
            }

            let visibleRect = clipView.documentVisibleRect
            let glyphRange = layoutManager.glyphRange(
                forBoundingRect: visibleRect, in: textContainer)
            let charRange = layoutManager.characterRange(
                forGlyphRange: glyphRange, actualGlyphRange: nil)

            let nsString = textView.string as NSString
            let textLength = nsString.length
            guard textLength > 0 else { return NSRange(location: 0, length: 0) }

            let bufferStart = max(0, charRange.location - buffer)
            let bufferEnd = min(textLength, NSMaxRange(charRange) + buffer)

            let startLineRange = nsString.lineRange(for: NSRange(location: bufferStart, length: 0))
            let endLineRange = nsString.lineRange(
                for: NSRange(location: min(bufferEnd, textLength - 1), length: 0))

            let start = startLineRange.location
            let end = NSMaxRange(endLineRange)

            return NSRange(location: start, length: end - start)
        }

        // MARK: - Scroll Observer

        func setupScrollObserver(for scrollView: NSScrollView, textView: NSTextView) {
            scrollView.contentView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self, weak textView] _ in
                guard let self, let textView else { return }
                self.scheduleScrollHighlighting(for: textView)
            }
        }

        private func scheduleScrollHighlighting(for textView: NSTextView) {
            pendingScrollWork?.cancel()
            let workItem = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView else { return }
                let visibleRange = self.visibleCharacterRange(in: textView)
                if let last = self.lastHighlightedVisibleRange,
                    last.location <= visibleRange.location,
                    NSMaxRange(last) >= NSMaxRange(visibleRange)
                {
                    return
                }
                self.lastHighlightedVisibleRange = visibleRange
                self.highlighter.applyHighlighting(to: textView, in: visibleRange)
            }
            pendingScrollWork = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + scrollDebounce, execute: workItem)
        }

        // MARK: - Initial Highlight

        func performInitialHighlight(for textView: NSTextView) {
            let textLength = (textView.string as NSString).length
            guard textLength > 0 else { return }

            pendingInitialWork?.cancel()

            let initialRange = initialHighlightRange(in: textView)
            highlighter.applyHighlighting(to: textView, in: initialRange)
            lastHighlightedVisibleRange = initialRange

            let workItem = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView else { return }
                guard (textView.string as NSString).length > 0 else { return }

                textView.layoutSubtreeIfNeeded()

                let visibleRange = self.visibleCharacterRange(in: textView)
                self.highlighter.applyHighlighting(to: textView, in: visibleRange)
                self.lastHighlightedVisibleRange = visibleRange
            }
            pendingInitialWork = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
        }

        private func initialHighlightRange(in textView: NSTextView) -> NSRange {
            let nsString = textView.string as NSString
            let textLength = nsString.length
            guard textLength > 0 else { return NSRange(location: 0, length: 0) }

            let visibleRange = visibleCharacterRange(in: textView, buffer: 2_000)
            let start = min(max(visibleRange.location, 0), textLength - 1)
            let minimumInitialLength = min(textLength - start, 12_000)
            let hasVisibleViewport =
                textView.enclosingScrollView?.contentView.documentVisibleRect.isEmpty == false
            let visibleEnd = hasVisibleViewport ? NSMaxRange(visibleRange) : start
            let end = min(textLength, max(visibleEnd, start + minimumInitialLength))
            let startLineRange = nsString.lineRange(for: NSRange(location: start, length: 0))
            let lineRange = nsString.lineRange(for: NSRange(location: max(0, end - 1), length: 0))

            return NSRange(
                location: startLineRange.location,
                length: NSMaxRange(lineRange) - startLineRange.location
            )
        }

        // MARK: - Text Editing

        public func textView(
            _ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            if parent.configuration.enablesLiveHighlighting {
                highlighter.prepareEdit(
                    in: affectedCharRange,
                    replacementString: replacementString,
                    currentText: textView.string
                )
            }
            return true
        }

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }

            parent.text = textView.string

            lastHighlightedVisibleRange = nil
            invalidateLineIndex()

            NotificationCenter.default.post(name: .yayTextDidEdit, object: nil)

            guard parent.configuration.enablesLiveHighlighting else { return }

            let cursorLocation = textView.selectedRange().location
            let editRange = expandedLineRange(
                around: cursorLocation, in: textView.string, lineBuffer: 3)
            scheduleIncrementalHighlighting(for: textView, range: editRange)

            scheduleVisibleRangeHighlighting(for: textView)
        }

        func scheduleIncrementalHighlighting(for textView: NSTextView, range: NSRange) {
            pendingIncrementalWork?.cancel()
            let workItem = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView else { return }
                let currentLength = (textView.string as NSString).length
                guard currentLength > 0 else { return }
                let validRange = NSIntersectionRange(
                    range, NSRange(location: 0, length: currentLength))
                guard validRange.length > 0 else { return }
                self.highlighter.applyHighlighting(to: textView, in: validRange)
            }
            pendingIncrementalWork = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + incrementalDebounce, execute: workItem)
        }

        func scheduleVisibleRangeHighlighting(for textView: NSTextView) {
            pendingFullWork?.cancel()
            let workItem = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView else { return }
                guard (textView.string as NSString).length > 0 else { return }
                let visibleRange = self.visibleCharacterRange(in: textView)
                self.highlighter.applyHighlighting(to: textView, in: visibleRange)
                self.lastHighlightedVisibleRange = visibleRange
            }
            pendingFullWork = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + fullDebounce, execute: workItem)
        }

        private func expandedLineRange(around cursor: Int, in text: String, lineBuffer: Int)
            -> NSRange
        {
            let nsString = text as NSString
            let length = nsString.length
            guard length > 0 else { return NSRange(location: 0, length: 0) }

            let safeCursor = min(cursor, length)
            let cursorLineRange = nsString.lineRange(for: NSRange(location: safeCursor, length: 0))

            var start = cursorLineRange.location
            for _ in 0..<lineBuffer {
                if start == 0 { break }
                start = nsString.lineRange(for: NSRange(location: start - 1, length: 0)).location
            }

            var end = NSMaxRange(cursorLineRange)
            for _ in 0..<lineBuffer {
                if end >= length { break }
                end = NSMaxRange(nsString.lineRange(for: NSRange(location: end, length: 0)))
            }

            return NSRange(location: start, length: end - start)
        }

        func invalidateLineIndex() {
            lineIndexDirty = true
        }

        private func ensureLineIndex(for nsString: NSString) {
            guard lineIndexDirty || lineIndexTextLength != nsString.length else { return }

            var starts = [0]
            starts.reserveCapacity(max(1, nsString.length / 80))

            var searchStart = 0
            while searchStart < nsString.length {
                let searchRange = NSRange(
                    location: searchStart, length: nsString.length - searchStart)
                let newlineRange = nsString.range(of: "\n", options: [], range: searchRange)
                if newlineRange.location == NSNotFound { break }

                searchStart = newlineRange.location + newlineRange.length
                if searchStart <= nsString.length {
                    starts.append(searchStart)
                }
            }

            lineStarts = starts
            lineIndexTextLength = nsString.length
            lineIndexDirty = false
        }

        private func sourceLineNumber(for charIndex: Int, in nsString: NSString) -> Int {
            ensureLineIndex(for: nsString)

            let safeIndex = min(max(charIndex, 0), nsString.length)
            var low = 0
            var high = lineStarts.count
            while low < high {
                let mid = (low + high) / 2
                if lineStarts[mid] <= safeIndex {
                    low = mid + 1
                } else {
                    high = mid
                }
            }
            return max(1, low)
        }

        private func characterIndex(forSourceLine line: Int, in nsString: NSString) -> Int {
            ensureLineIndex(for: nsString)

            guard line > 1 else { return 0 }
            let index = min(line - 1, lineStarts.count - 1)
            guard index >= 0 else { return 0 }
            return min(lineStarts[index], nsString.length)
        }
    }
}

extension Notification.Name {
    static let yayTextDidEdit = Notification.Name("yayTextDidEdit")
}

#endif
