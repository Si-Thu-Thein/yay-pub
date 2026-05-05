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
//  view bookkeeping (attach, navigate via UITextView selection, scroll
//  into view) is platform-specific.
//
//  Highlighting note: AppKit's NSLayoutManager exposes a full temporary-
//  attributes API; UIKit's does not. Rather than overlay UIView rects or
//  borrow UIFindInteraction (iOS 16+ only, and we still target iOS 15),
//  this first cut highlights *only the current match* via UITextView's
//  built-in selection. A future pass can layer on a multi-match overlay.
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
    private var searchDebounce: AnyCancellable?

    /// Bind the finder to a text view. Idempotent for the same view.
    public func attach(textView: UITextView) {
        if self.textView === textView { return }
        self.textView = textView
        cachedMatches = nil
        matchCount = 0
        currentMatchIndex = 0
        scheduleCountIfNeeded()
    }

    /// Stop counting and forget the text view. Call when the document
    /// closes; the find-bar dismiss path doesn't need it.
    public func detach() {
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
        guard !matches.isEmpty else { return }

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
        }
    }

    // MARK: - Cache & search

    private func invalidateCache() {
        cachedMatches = nil
        matchCount = 0
        currentMatchIndex = 0
        scheduleCountIfNeeded()
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

    /// Run the search after a short debounce so the count updates without
    /// firing the (potentially expensive) regex on every keystroke.
    private func scheduleCountIfNeeded() {
        guard !findString.isEmpty else {
            searchDebounce = nil
            return
        }
        searchDebounce = Just(())
            .delay(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, !self.findString.isEmpty else { return }
                _ = self.ensureMatches()
            }
    }

    @discardableResult
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
}
#endif
