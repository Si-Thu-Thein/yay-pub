#if os(macOS)
import AppKit
import Combine

@MainActor
final class TextFinder: ObservableObject {
    @Published var matchCount: Int = 0
    @Published var currentMatchIndex: Int = 0
    @Published var findString: String = "" {
        didSet {
            guard oldValue != findString else { return }
            invalidateCache(reason: "findString")
        }
    }
    @Published var isCaseSensitive: Bool = false {
        didSet {
            guard oldValue != isCaseSensitive else { return }
            invalidateCache(reason: "caseSensitive")
        }
    }
    @Published var isRegularExpression: Bool = false {
        didSet {
            guard oldValue != isRegularExpression else { return }
            invalidateCache(reason: "regex")
        }
    }
    @Published var isWholeWord: Bool = false {
        didSet {
            guard oldValue != isWholeWord else { return }
            invalidateCache(reason: "wholeWord")
        }
    }
    @Published var isWrap: Bool = true
    @Published var replacementString: String = ""

    private struct TemporaryBackgroundRun {
        let range: NSRange
        let value: Any?
    }

    private weak var textView: NSTextView?
    private let attachedTextViews = NSHashTable<NSTextView>.weakObjects()
    private var cachedMatches: [NSRange]?
    private var searchBackgroundRuns: [TemporaryBackgroundRun] = []
    private var matchCountValue: Int = 0
    private var currentMatchIndexValue: Int = 0
    private var textVersion: Int = 0
    private var cancellables = Set<AnyCancellable>()
    private var activeTextStorageCancellable: AnyCancellable?
    private var searchDebounce: AnyCancellable?

    init() {
        NotificationCenter.default.publisher(for: NSTextView.didChangeSelectionNotification)
            .sink { [weak self] notification in
                guard let textView = notification.object as? NSTextView else { return }
                self?.activateIfAttached(textView)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
            .sink { [weak self] notification in
                guard let window = notification.object as? NSWindow else { return }
                self?.activateTextView(in: window)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWindow.didBecomeMainNotification)
            .sink { [weak self] notification in
                guard let window = notification.object as? NSWindow else { return }
                self?.activateTextView(in: window)
            }
            .store(in: &cancellables)
    }

    func attach(textView: NSTextView) {
        if !attachedTextViews.contains(textView) {
            attachedTextViews.add(textView)
        }

        guard textView.window?.isKeyWindow == true
                || textView.window?.isMainWindow == true
                || textView.window?.firstResponder === textView
        else { return }

        activate(textView)
    }

    func activateFocusedTextView() {
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
           attachedTextViews.contains(textView)
        {
            activate(textView)
            return
        }

        if let textView = NSApp.mainWindow?.firstResponder as? NSTextView,
           attachedTextViews.contains(textView)
        {
            activate(textView)
            return
        }

        guard let window = NSApp.mainWindow ?? NSApp.keyWindow else { return }
        activateTextView(in: window)
    }

    private func activateIfAttached(_ textView: NSTextView) {
        guard attachedTextViews.contains(textView) else { return }
        activate(textView)
    }

    private func activateTextView(in window: NSWindow) {
        for case let textView as NSTextView in attachedTextViews.allObjects where textView.window === window {
            activate(textView)
            return
        }
    }

    private func activate(_ textView: NSTextView) {
        if self.textView === textView { return }
        clearHighlights()
        self.textView = textView
        cachedMatches = nil
        setSearchState(matchCount: 0, currentMatchIndex: 0)

        activeTextStorageCancellable = NotificationCenter.default
            .publisher(for: NSTextStorage.didProcessEditingNotification, object: textView.textStorage)
            .sink { [weak self] notification in
                guard let storage = notification.object as? NSTextStorage else { return }
                guard storage.editedMask.contains(.editedCharacters) else {
                    return
                }
                self?.invalidateCache(reason: "textCharactersChanged")
            }

        scheduleHighlightIfNeeded()
    }

    func invalidateCache(reason: String = "unknown") {
        cachedMatches = nil
        textVersion += 1
        setSearchState(matchCount: 0, currentMatchIndex: 0)
        scheduleHighlightIfNeeded()
    }

    private func scheduleHighlightIfNeeded() {
        guard !findString.isEmpty else {
            searchDebounce = nil
            clearHighlights()
            return
        }
        searchDebounce = Just(())
            .delay(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, !self.findString.isEmpty else { return }
                self.highlightAll()
            }
    }

    private var currentFindOptions: FindOptions {
        FindOptions(
            findString: findString,
            replacementString: replacementString,
            isCaseSensitive: isCaseSensitive,
            isRegularExpression: isRegularExpression,
            isWholeWord: isWholeWord,
            isWrap: isWrap
        )
    }

    private func ensureMatches() -> [NSRange] {
        if let cached = cachedMatches { return cached }

        guard let textView,
              !findString.isEmpty
        else {
            cachedMatches = []
            setSearchState(matchCount: 0, currentMatchIndex: 0)
            return []
        }

        do {
            let textFind = try TextFind(
                string: textView.string,
                findString: findString,
                options: currentFindOptions
            )
            let results = textFind.matches()
            cachedMatches = results
            setSearchState(matchCount: results.count, currentMatchIndex: results.isEmpty ? 0 : 1)
            return results
        } catch {
            cachedMatches = []
            setSearchState(matchCount: 0, currentMatchIndex: 0)
            return []
        }
    }

    func performFind(forward: Bool) {
        guard let textView else { return }
        let matches = ensureMatches()
        guard !matches.isEmpty else {
            clearHighlights()
            return
        }

        let selectedRange = textView.selectedRange()
        var location: Int
        if forward {
            location = NSMaxRange(selectedRange)
        } else {
            location = selectedRange.location
        }

        if selectedRange.length == 0,
           matches.indices.contains(currentMatchIndexValue - 1)
        {
            let currentMatch = matches[currentMatchIndexValue - 1]
            if currentMatch.length == 0 && currentMatch.location == selectedRange.location {
                location += forward ? 1 : -1
            }
        }

        let textFind = try? TextFind(
            string: textView.string,
            findString: findString,
            options: currentFindOptions
        )

        if let match = textFind?.findNext(after: location, forward: forward, wraps: isWrap) {
            if let idx = matches.firstIndex(of: match) {
                setSearchState(matchCount: matches.count, currentMatchIndex: idx + 1)
            }
            textView.setSelectedRange(match)
            textView.scrollRangeToVisible(match)
            highlightAll()
        }
    }

    func performReplace() {
        guard let textView else { return }
        let matches = ensureMatches()
        guard !matches.isEmpty else { return }

        let sel = textView.selectedRange()
        if let match = matches.first(where: { NSIntersectionRange($0, sel).length > 0 }) {
            let textFind = try? TextFind(
                string: textView.string,
                findString: findString,
                options: currentFindOptions
            )
            let replacement = textFind?.replacementString(for: match, with: replacementString) ?? replacementString
            replaceRange(match, with: replacement, in: textView)
            invalidateCache()
            performFind(forward: true)
        } else {
            performFind(forward: true)
        }
    }

    func performReplaceAll() -> Int {
        guard let textView else { return 0 }
        let matches = ensureMatches()
        guard !matches.isEmpty else { return 0 }

        clearHighlights()

        let textFind = try? TextFind(
            string: textView.string,
            findString: findString,
            options: currentFindOptions
        )

        let reversedMatches = matches.reversed()
        var totalReplaced = 0

        if textView.shouldChangeText(in: NSRange(location: 0, length: (textView.string as NSString).length), replacementString: nil) {
            textView.textStorage?.beginEditing()
            for match in reversedMatches {
                let replacement = textFind?.replacementString(for: match, with: replacementString) ?? replacementString
                textView.textStorage?.replaceCharacters(in: match, with: replacement)
                totalReplaced += 1
            }
            textView.textStorage?.endEditing()
            textView.didChangeText()
        }

        invalidateCache()
        return totalReplaced
    }

    func highlightAll() {
        guard let textView else { return }
        let matches = ensureMatches()
        guard let layoutManager = textView.layoutManager as? MarkdownLayoutManager
        else { return }

        let textLength = (textView.string as NSString).length
        restoreSearchHighlights(using: layoutManager, textLength: textLength)

        let visibleMatches = matches.compactMap { clampedPositiveRange($0, textLength: textLength) }
        guard !visibleMatches.isEmpty else { return }

        let invalidationRange = unionRange(visibleMatches)
        let highlightColor = NSColor.systemYellow.withAlphaComponent(0.4)
        let currentColor = NSColor.systemOrange.withAlphaComponent(0.6)

        layoutManager.groupTemporaryAttributesUpdate(in: invalidationRange) {
            self.searchBackgroundRuns = visibleMatches.flatMap {
                self.temporaryBackgroundRuns(in: $0, layoutManager: layoutManager)
            }

            for (index, match) in matches.enumerated() {
                guard let match = self.clampedPositiveRange(match, textLength: textLength) else { continue }
                let color = (index == self.currentMatchIndexValue - 1) ? currentColor : highlightColor
                layoutManager.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: match)
            }
        }
    }

    func clearHighlights() {
        searchDebounce = nil
        guard let textView,
              let layoutManager = textView.layoutManager as? MarkdownLayoutManager
        else {
            searchBackgroundRuns.removeAll()
            return
        }

        let textLength = (textView.string as NSString).length
        restoreSearchHighlights(using: layoutManager, textLength: textLength)
    }

    var matchDescription: String {
        if findString.isEmpty { return "" }
        if matchCount == 0 { return "No results" }
        return "\(currentMatchIndex) of \(matchCount)"
    }

    private func replaceRange(_ range: NSRange, with string: String, in textView: NSTextView) {
        guard textView.shouldChangeText(in: range, replacementString: string) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: string)
        textView.didChangeText()
    }

    private func temporaryBackgroundRuns(
        in range: NSRange,
        layoutManager: NSLayoutManager
    ) -> [TemporaryBackgroundRun] {
        var runs: [TemporaryBackgroundRun] = []
        var location = range.location
        let end = NSMaxRange(range)

        while location < end {
            var effectiveRange = NSRange(location: location, length: end - location)
            let attributes = layoutManager.temporaryAttributes(
                atCharacterIndex: location,
                effectiveRange: &effectiveRange
            )
            let clippedRange = NSIntersectionRange(effectiveRange, range)
            if clippedRange.length > 0 {
                runs.append(TemporaryBackgroundRun(
                    range: clippedRange,
                    value: attributes[.backgroundColor]
                ))
            }
            location = max(NSMaxRange(clippedRange), location + 1)
        }

        return runs
    }

    private func restoreSearchHighlights(using layoutManager: MarkdownLayoutManager, textLength: Int) {
        let runs = searchBackgroundRuns.compactMap { run -> TemporaryBackgroundRun? in
            guard let range = clampedPositiveRange(run.range, textLength: textLength) else { return nil }
            return TemporaryBackgroundRun(range: range, value: run.value)
        }
        searchBackgroundRuns.removeAll()

        guard !runs.isEmpty else { return }

        layoutManager.groupTemporaryAttributesUpdate(in: unionRange(runs.map(\.range))) {
            for run in runs {
                if let value = run.value {
                    layoutManager.addTemporaryAttribute(
                        .backgroundColor,
                        value: value,
                        forCharacterRange: run.range
                    )
                } else {
                    layoutManager.removeTemporaryAttribute(
                        .backgroundColor,
                        forCharacterRange: run.range
                    )
                }
            }
        }
    }

    private func clampedPositiveRange(_ range: NSRange, textLength: Int) -> NSRange? {
        let textRange = NSRange(location: 0, length: textLength)
        let clamped = NSIntersectionRange(range, textRange)
        return clamped.length > 0 ? clamped : nil
    }

    private func unionRange(_ ranges: [NSRange]) -> NSRange {
        guard let first = ranges.first else { return NSRange(location: 0, length: 0) }
        var lower = first.location
        var upper = NSMaxRange(first)

        for range in ranges.dropFirst() {
            lower = min(lower, range.location)
            upper = max(upper, NSMaxRange(range))
        }

        return NSRange(location: lower, length: upper - lower)
    }

    private func setSearchState(matchCount: Int, currentMatchIndex: Int) {
        matchCountValue = matchCount
        currentMatchIndexValue = currentMatchIndex

        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.matchCountValue == matchCount,
                  self.currentMatchIndexValue == currentMatchIndex
            else { return }

            if self.matchCount != matchCount {
                self.matchCount = matchCount
            }
            if self.currentMatchIndex != currentMatchIndex {
                self.currentMatchIndex = currentMatchIndex
            }
        }
    }
}

#endif
