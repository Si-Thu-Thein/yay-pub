#if os(macOS)
import SwiftUI

struct FindPanelView: View {
    @ObservedObject var textFinder: TextFinder

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                findRow
                replaceRow
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 10)

            Divider()

            optionsBar
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
        }
    }

    // MARK: - Find Row

    private var findRow: some View {
        HStack(spacing: 6) {
            ZStack(alignment: .trailing) {
                PanelTextField(
                    placeholder: "Find",
                    text: $textFinder.findString,
                    onCommit: {
                        textFinder.performFind(forward: true)
                    }
                )

                if !textFinder.findString.isEmpty {
                    Text(textFinder.matchDescription)
                        .font(.system(size: 10))
                        .foregroundColor(textFinder.matchCount == 0 ? .red : Color(NSColor.tertiaryLabelColor))
                        .padding(.trailing, 6)
                        .allowsHitTesting(false)
                }
            }

            ControlGroup {
                Button {
                    textFinder.performFind(forward: false)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                }
                .disabled(textFinder.findString.isEmpty)

                Button {
                    textFinder.performFind(forward: true)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .disabled(textFinder.findString.isEmpty)
            }
            .controlSize(.small)
            .frame(width: 52)
        }
    }

    // MARK: - Replace Row

    private var replaceRow: some View {
        HStack(spacing: 6) {
            PanelTextField(placeholder: "Replace", text: $textFinder.replacementString)

            Button("Replace") {
                textFinder.performReplace()
            }
            .controlSize(.small)
            .disabled(textFinder.matchCount == 0)

            Button("Replace All") {
                _ = textFinder.performReplaceAll()
            }
            .controlSize(.small)
            .disabled(textFinder.matchCount == 0)
        }
    }

    // MARK: - Options Bar

    private var optionsBar: some View {
        HStack(spacing: 4) {
            OptionToggle(label: "Aa", tooltip: "Case Sensitive", isOn: $textFinder.isCaseSensitive)
            OptionToggle(label: "\\b", tooltip: "Whole Word", isOn: $textFinder.isWholeWord)
            OptionToggle(label: ".*", tooltip: "Regular Expression", isOn: $textFinder.isRegularExpression)

            Spacer()

            Button("Done") {
                textFinder.clearHighlights()
                FindPanelController.shared.hidePanel()
            }
            .controlSize(.small)
        }
    }
}

// MARK: - Option Toggle Button

private struct OptionToggle: View {
    let label: String
    let tooltip: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(isOn ? .accentColor : Color(NSColor.secondaryLabelColor))
                .frame(width: 28, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isOn ? Color.accentColor.opacity(0.12) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            isOn ? Color.accentColor.opacity(0.4) : Color(NSColor.separatorColor),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}

// MARK: - Single-line Text Field

private struct PanelTextField: NSViewRepresentable {
    typealias NSViewType = NSTextField

    var placeholder: String
    @Binding var text: String
    var onCommit: (() -> Void)?

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.font = .systemFont(ofSize: 13)
        field.bezelStyle = .roundedBezel
        field.isBordered = true
        field.isBezeled = true
        (field.cell as? NSTextFieldCell)?.isScrollable = true
        (field.cell as? NSTextFieldCell)?.wraps = false
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        let onCommit: (() -> Void)?

        init(text: Binding<String>, onCommit: (() -> Void)?) {
            self._text = text
            self.onCommit = onCommit
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let editor = notification.userInfo?["NSFieldEditor"] as? NSTextView else { return }
            editor.isAutomaticDashSubstitutionEnabled = false
            editor.isAutomaticDataDetectionEnabled = false
            editor.isAutomaticLinkDetectionEnabled = false
            editor.isAutomaticQuoteSubstitutionEnabled = false
            editor.isAutomaticSpellingCorrectionEnabled = false
            editor.isAutomaticTextCompletionEnabled = false
            editor.isAutomaticTextReplacementEnabled = false
            editor.isContinuousSpellCheckingEnabled = false
            editor.isGrammarCheckingEnabled = false
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                if let field = control as? NSTextField {
                    let currentText = field.stringValue
                    if text != currentText {
                        text = currentText
                    }
                }
                onCommit?()
                return true
            default:
                return false
            }
        }
    }
}

#endif
