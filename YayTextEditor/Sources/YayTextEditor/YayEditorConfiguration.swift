import Foundation
import YayCore

//
//  YayEditorConfiguration.swift
//  Yay
//
//  Created by Saturngod on 8/29/25.
//

public struct YayEditorConfiguration {
    public var theme: MarkdownTheme
    public var lineFragmentPadding: CGFloat
    public var textContainerInset: CGSize
    public var lineHeightMultiple: CGFloat
    public var enablesLiveHighlighting: Bool
    public var focusOnAppear: Bool

    public init(
        theme: MarkdownTheme, lineFragmentPadding: CGFloat, textContainerInset: CGSize,
        lineHeightMultiple: CGFloat = 1.5, enablesLiveHighlighting: Bool, focusOnAppear: Bool
    ) {
        self.theme = theme
        self.lineFragmentPadding = lineFragmentPadding
        self.textContainerInset = textContainerInset
        self.lineHeightMultiple = lineHeightMultiple
        self.enablesLiveHighlighting = enablesLiveHighlighting
        self.focusOnAppear = focusOnAppear
    }

    public static let standard = YayEditorConfiguration(
        theme: .githubLight,
        lineFragmentPadding: 5,
        textContainerInset: CGSize(width: 5, height: 5),
        lineHeightMultiple: 1.5,
        enablesLiveHighlighting: true,
        focusOnAppear: true
    )
}
