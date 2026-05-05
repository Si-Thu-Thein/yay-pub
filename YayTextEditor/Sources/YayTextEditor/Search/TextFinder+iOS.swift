#if os(iOS)
import UIKit
import Combine

//
//  TextFinder+iOS.swift
//  Yay (iPad port — Phase 4)
//
//  iOS counterpart to TextFinder.swift. Drives an in-document find bar
//  (FindBarView+iOS) over a single attached UITextView. The match search
//  itself reuses TextFind/FindOptions from this package; only the host
//  view bookkeeping (attach, highlight via NSLayoutManager temporary
//  attributes, scroll into view) is platform-specific.
//
//  Replace is intentionally out of scope for the first iPad cut: the iOS
//  on-screen keyboard makes a two-field find/replace bar awkward, and
//  no iPad surface needs it before TestFlight. Add later if requested.
//

@MainActor
public final class IOSTextFinder: ObservableObject {
    @Published public var findString: String = "" {
        didSet {
            guard oldValue != findString else { return }
            invalidateCache()
        }
    }
    @Published public var isCaseSensitive: Bool = false {
        didSet {
            guard oldValue != isCaseSensitive else { return }
            invalidateCache()
        }
    }
    @Published public var isRegularExpression: Bool = false {
        didSet {
            guard oldValue != isRegularExpression else { return }
            invalidateCache()
        }
    }
    @Published public var isWholeWord: Bool = false {
        didSet {
            guard oldValue != isWholeWord else { return }
            invalidateCache()
        }
    }
    @Published public var isWrap: Bool = true

    @Published public private(set) var matchCount: Int = 0
    @Published public private(set) var currentMatchIndex: Int = 0

    public init() {}

    public var matchDescription: String {
        if findString.isEmpty { return "" }
        if matchCount == 0 { return "No results" }
        return "\(currentMatchIndex) of \(matchCount)"
    }

    // MARK: - Attach / detach

    private weak var textView: UITextView?
    private var cachedMatches: [NSRange]?
    /// Ranges currently carrying a search-highlight temporary attribute.
    /// Cleared via setTemporaryAttributes(_:forCharacterRange:) with an
    /// empty dict on the next pass — UIKit's NSLayoutManager has no
    /// removeTemporaryAttribute(_:forCharacterRange:) helper.
    private var highlightedRanges: [NSRange] = []
    private var searchDebounce: AnyCancellable?

    /// Bind the finder to a text view. Must be called after the view is
    /// installed in a window so the layout manager has a usable text storage.
    public func attach(textView: UITextView) {
        if self.textView === textView { return }
        clearHighlights()
        self.textView = textView
        cachedMatches = nil
        matchCount = 0
        currentMatchIndex = 0
        scheduleHighlightIfNeeded()
    }

    /// Stop highlighting and forget the text view. Call when the find bar
    /// is dismissed so leftover yellow backgrounds don't linger.
    public func detach() {
        clearHighlights()
        textView = nil
        cachedMatches = nil
        matchCount = 0
        currentMatchIndex = 0
        searchDebounce = nil
    }

    /// Call from the editor's text-change delegate so the cache is rebuilt
    /// after edits. The host view (YayTextEditor+iOS) wires this up.
    public func textDidChange() {
        invalidateCache()
    }

    // MARK: - Find / navigate

    public func findNext() { performFind(forward: true) }
    public func findPrevious() { performFind(forward: false) }

    private func performFind(forward: Bool) {
        guard let textView else { return }
        let matches = ensureMatches()
        guard !matches.isEmpty else {
            clearHighlights()
            return
        }

        let selected = textView.selectedRange
        var location: Int
        if forward {
            location = NSMaxRange(selected)
        } else {
            location = selected.location
        }

        // If the caret sits on a zero-length match (e.g. regex `(?=...)`),
        // step past it so we don't loop forever.
        if selected.length == 0,
           matches.indices.contains(currentMatchIndex - 1)
        {
            let current = matches[currentMatchIndex - 1]
            if current.length == 0 && current.location == selected.location {
                location += forward ? 1 : -1
            }
        }

        guard let textFind = try? TextFind(
            string: textView.text ?? "",
            findString: findString,
            options: currentFindOptions
        ) else { return }

        if let match = textFind.findNext(after: location, forward: forward, wraps: isWrap) {
            if let idx = matches.firstIndex(of: match) {
                currentMatchIndex = idx + 1
            }
            textView.selectedRange = match
            textView.scrollRangeToVisible(match)
            highlightAll()
        }
    }

    // MARK: - Cache & search

    private func invalidateCache() {
        cachedMatches = nil
        matchCount = 0
        currentMatchIndex = 0
        scheduleHighlightIfNeeded()
    }

    private var currentFindOptions: FindOptions {
        FindOptions(
            findString: findString,
            replacementString: "",
            isCaseSensitive: isCaseSensitive,
            isRegularExpression: isRegularExpression,
            isWholeWord: isWholeWord,
            isWrap: isWrap
        )
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

    private func ensureMatches() -> [NSRange] {
        if let cached = cachedMatches { return cached }

        guard let textView,
              !findString.isEmpty
        else {
            cachedMatches = []
            matchCount = 0
            currentMatchIndex = 0
            return []
        }

        do {
            let textFind = try TextFind(
                string: textView.text ?? "",
                findString: findString,
                options: currentFindOptions
            )
            let results = textFind.matches()
            cachedMatches = results
            matchCount = results.count
            currentMatchIndex = results.isEmpty ? 0 : 1
            return results
        } catch {
            cachedMatches = []
            matchCount = 0
            currentMatchIndex = 0
            return []
        }
    }

    // MARK: - Highlight

    /// Apply the yellow/orange search backgrounds. Clears any prior search
    /// highlights first. UIKit's NSLayoutManager exposes only
    /// `setTemporaryAttributes(_:forCharacterRange:)` (replaces all temp
    /// attrs in the range) — no add/remove/query — so we simply track the
    /// ranges we set and `set([:])` them to clear. Nothing else in this
    /// codebase writes temporary attributes, so blanket clearing is safe.
    private func highlightAll() {
        guard let textView else { return }
        let matches = ensureMatches()
        guard let layoutManager = textView.layoutManager as? MarkdownLayoutManager
        else { return }

        let textLength = (textView.text as NSString?)?.length ?? 0
        let visible = matches.compactMap { clampedPositiveRange($0, textLength: textLength) }

        let highlightColor = UIColor.systemYellow.withAlphaComponent(0.4)
        let currentColor = UIColor.systemOrange.withAlphaComponent(0.6)

        let invalidationRange: NSRange = {
            let allRanges = highlightedRanges + visible
            return allRanges.isEmpty
                ? NSRange(location: 0, length: textLength)
                : unionRange(allRanges)
        }()

        layoutManager.groupTemporaryAttributesUpdate(in: invalidationRange) {
            for prev in self.highlightedRanges {
                guard let r = self.clampedPositiveRange(prev, textLength: textLength) else { continue }
                layoutManager.setTemporaryAttributes([:], forCharacterRange: r)
            }
            self.highlightedRanges.removeAll(keepingCapacity: true)

            for (index, match) in matches.enumerated() {
                guard let m = self.clampedPositiveRange(match, textLength: textLength) else { continue }
                let color = (index == self.currentMatchIndex - 1) ? currentColor : highlightColor
                layoutManager.setTemporaryAttributes([.backgroundColor: color], forCharacterRange: m)
                self.highlightedRanges.append(m)
            }
        }
    }

    private func clearHighlights() {
        searchDebounce = nil
        guard let textView,
              let layoutManager = textView.layoutManager as? MarkdownLayoutManager
        else {
            highlightedRanges.removeAll()
            return
        }
        guard !highlightedRanges.isEmpty else { return }

        let textLength = (textView.text as NSString?)?.length ?? 0
        let invalidationRange = unionRange(highlightedRanges)
        layoutManager.groupTemporaryAttributesUpdate(in: invalidationRange) {
            for prev in self.highlightedRanges {
                guard let r = self.clampedPositiveRange(prev, textLength: textLength) else { continue }
                layoutManager.setTemporaryAttributes([:], forCharacterRange: r)
            }
            self.highlightedRanges.removeAll(keepingCapacity: true)
        }
    }

    private func clampedPositiveRange(_ range: NSRange, textLength: Int) -> NSRange? {
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: textLength))
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
}
#endif
