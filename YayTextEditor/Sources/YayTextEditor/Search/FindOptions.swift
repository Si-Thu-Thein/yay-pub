import Foundation

public struct FindOptions: Equatable {
    public var findString: String
    public var replacementString: String
    public var isCaseSensitive: Bool
    public var isRegularExpression: Bool
    public var isWholeWord: Bool
    public var isWrap: Bool

    public init(
        findString: String = "",
        replacementString: String = "",
        isCaseSensitive: Bool = false,
        isRegularExpression: Bool = false,
        isWholeWord: Bool = false,
        isWrap: Bool = true
    ) {
        self.findString = findString
        self.replacementString = replacementString
        self.isCaseSensitive = isCaseSensitive
        self.isRegularExpression = isRegularExpression
        self.isWholeWord = isWholeWord
        self.isWrap = isWrap
    }

    var compareOptions: String.CompareOptions {
        var options: String.CompareOptions = []
        if !isCaseSensitive { options.insert(.caseInsensitive) }
        return options
    }

    var regexOptions: NSRegularExpression.Options {
        var options: NSRegularExpression.Options = []
        if !isCaseSensitive { options.insert(.caseInsensitive) }
        return options
    }
}
