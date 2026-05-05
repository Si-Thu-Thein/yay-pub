#if os(iOS)
import SwiftUI

//
//  FindBarView+iOS.swift
//  Yay (iPad port — Phase 4)
//
//  SwiftUI find bar for iPad. Renders above the editor (or above the
//  keyboard, depending on layout) and drives an IOSTextFinder. The bar
//  is a public View so the iPad app target can drop it in without
//  reaching into package-private types.
//

public struct FindBarView: View {
    @ObservedObject private var finder: IOSTextFinder
    private let onDismiss: () -> Void

    @FocusState private var isFieldFocused: Bool

    public init(finder: IOSTextFinder, onDismiss: @escaping () -> Void) {
        self.finder = finder
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))

            TextField("Find", text: $finder.findString)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)
                .focused($isFieldFocused)
                .onSubmit { finder.findNext() }
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !finder.matchDescription.isEmpty {
                Text(finder.matchDescription)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Match status: \(finder.matchDescription)")
            }

            Group {
                Button {
                    finder.findPrevious()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .accessibilityLabel("Previous match")
                .disabled(finder.matchCount == 0)

                Button {
                    finder.findNext()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .accessibilityLabel("Next match")
                .disabled(finder.matchCount == 0)
            }
            .buttonStyle(.bordered)

            Menu {
                Toggle("Match Case", isOn: $finder.isCaseSensitive)
                Toggle("Whole Word", isOn: $finder.isWholeWord)
                Toggle("Regular Expression", isOn: $finder.isRegularExpression)
                Toggle("Wrap Around", isOn: $finder.isWrap)
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .accessibilityLabel("Find options")

            Button("Done") {
                onDismiss()
            }
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .onAppear {
            // Focus the field automatically so a Cmd+F press goes straight
            // to typing. Slight async delay because the bar is animated in.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFieldFocused = true
            }
        }
    }
}
#endif
