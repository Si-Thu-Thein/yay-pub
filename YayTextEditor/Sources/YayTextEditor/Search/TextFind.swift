import Foundation

struct TextFind {
    enum Mode {
        case textual(options: String.CompareOptions, wholeWord: Bool)
        case regularExpression(options: NSRegularExpression.Options)
    }

    enum FindError: Error, LocalizedError {
        case emptyFindString
        case invalidRegularExpression(String)

        var errorDescription: String? {
            switch self {
            case .emptyFindString:
                return "The find string is empty."
            case .invalidRegularExpression(let reason):
                return "Invalid regular expression: \(reason)"
            }
        }
    }

    let string: NSString
    let findString: String
    let mode: Mode
    let searchRange: NSRange

    init(string: String, findString: String, options: FindOptions) throws {
        guard !findString.isEmpty else { throw FindError.emptyFindString }

        self.string = string as NSString
        self.findString = findString

        if options.isRegularExpression {
            self.mode = .regularExpression(options: options.regexOptions)
            guard let _ = try? NSRegularExpression(pattern: findString, options: options.regexOptions)
            else {
                throw FindError.invalidRegularExpression(findString)
            }
        } else {
            self.mode = .textual(options: options.compareOptions, wholeWord: options.isWholeWord)
        }

        self.searchRange = NSRange(location: 0, length: self.string.length)
    }

    func matches() -> [NSRange] {
        switch mode {
        case .textual(let options, let wholeWord):
            return textualMatches(options: options, wholeWord: wholeWord)
        case .regularExpression(let options):
            return regexMatches(options: options)
        }
    }

    func findNext(after location: Int, forward: Bool, wraps: Bool) -> NSRange? {
        let all = matches()
        guard !all.isEmpty else { return nil }

        if forward {
            if let match = all.first(where: { $0.location >= location }) {
                return match
            }
            return wraps ? all.first : nil
        } else {
            if let match = all.last(where: { NSMaxRange($0) <= location }) {
                return match
            }
            return wraps ? all.last : nil
        }
    }

    func replacementString(for match: NSRange, with template: String) -> String {
        switch mode {
        case .textual:
            return template
        case .regularExpression(let options):
            guard let regex = try? NSRegularExpression(pattern: findString, options: options),
                  let result = regex.firstMatch(in: string as String, options: [], range: match)
            else { return template }
            return regex.replacementString(for: result, in: string as String, offset: 0, template: template)
        }
    }

    private func textualMatches(options: String.CompareOptions, wholeWord: Bool) -> [NSRange] {
        var results = [NSRange]()
        var searchFrom = searchRange.location
        let end = NSMaxRange(searchRange)

        while searchFrom < end {
            let remaining = NSRange(location: searchFrom, length: end - searchFrom)
            let found = string.range(of: findString, options: options, range: remaining)
            if found.location == NSNotFound { break }

            if wholeWord {
                if isWordBoundary(at: found.location) && isWordBoundary(at: NSMaxRange(found)) {
                    results.append(found)
                }
            } else {
                results.append(found)
            }

            searchFrom = NSMaxRange(found) > found.location ? NSMaxRange(found) : found.location + 1
        }
        return results
    }

    private func regexMatches(options: NSRegularExpression.Options) -> [NSRange] {
        guard let regex = try? NSRegularExpression(pattern: findString, options: options)
        else { return [] }
        return regex.matches(in: string as String, options: [], range: searchRange).map(\.range)
    }

    private func isWordBoundary(at index: Int) -> Bool {
        guard index >= 0, index <= string.length else { return true }
        if index == 0 || index == string.length { return true }
        let prev = string.character(at: index - 1)
        let curr = string.character(at: index)
        let prevIsWord = CharacterSet.alphanumerics.contains(UnicodeScalar(prev) ?? UnicodeScalar(0))
        let currIsWord = CharacterSet.alphanumerics.contains(UnicodeScalar(curr) ?? UnicodeScalar(0))
        return prevIsWord != currIsWord
    }
}
