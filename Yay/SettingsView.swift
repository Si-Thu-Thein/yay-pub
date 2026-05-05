import SwiftUI
import AppKit

// MARK: - General

struct GeneralSettingsPane: View {
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Keyboard Shortcuts")
                        .font(.headline)
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 4) {
                        GridRow { Text("New Document").foregroundStyle(.secondary); Text("⌘N").monospaced() }
                        GridRow { Text("New Tab").foregroundStyle(.secondary); Text("⌘T").monospaced() }
                        GridRow { Text("Open File").foregroundStyle(.secondary); Text("⌘O").monospaced() }
                        GridRow { Text("Open Folder").foregroundStyle(.secondary); Text("⇧⌘O").monospaced() }
                        GridRow { Text("Toggle Preview").foregroundStyle(.secondary); Text("⌘R").monospaced() }
                        GridRow { Text("Find").foregroundStyle(.secondary); Text("⌘F").monospaced() }
                        GridRow { Text("Toggle Sidebar").foregroundStyle(.secondary); Text("⌃⌘S").monospaced() }
                        GridRow { Text("Export HTML").foregroundStyle(.secondary); Text("⇧⌘E").monospaced() }
                        GridRow { Text("Export PDF").foregroundStyle(.secondary); Text("⇧⌘P").monospaced() }
                    }
                    .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Editor

struct EditorSettingsPane: View {
    @AppStorage("editorFontFamily") private var fontFamily = "Menlo"
    @AppStorage("editorFontSize") private var fontSize: Double = 14
    @AppStorage("editorLineHeight") private var lineHeight: Double = 1.5

    private let allFamilies = NSFontManager.shared.availableFontFamilies

    var body: some View {
        Form {
            Section("Font") {
                Picker("Family", selection: $fontFamily) {
                    ForEach(allFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                .pickerStyle(.menu)
                .onAppear {
                    if !allFamilies.contains(fontFamily) {
                        fontFamily = "Menlo"
                    }
                }

                HStack {
                    Text("Size")
                    Spacer()
                    TextField("", value: $fontSize, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 52)
                        .textFieldStyle(.roundedBorder)
                    Stepper("", value: $fontSize, in: 8...72, step: 1)
                        .labelsHidden()
                }

                HStack {
                    Text("Line Height")
                    Spacer()
                    TextField("", value: $lineHeight, format: .number.precision(.fractionLength(1)))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 52)
                        .textFieldStyle(.roundedBorder)
                    Stepper("", value: $lineHeight, in: 1.0...3.0, step: 0.1)
                        .labelsHidden()
                }

                Button("Reset to Defaults") {
                    fontFamily = "Menlo"
                    fontSize = 14
                    lineHeight = 1.5
                }
                .font(.callout)
            }

            Section("Preview") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("# Heading")
                        .font(.custom(fontFamily, size: CGFloat(fontSize * 1.6)).weight(.bold))
                        .foregroundStyle(.primary)

                    Text("A paragraph with **bold**, *italic*, and `code` text.")
                        .font(.custom(fontFamily, size: CGFloat(fontSize)))
                        .foregroundStyle(.primary)

                    Text("1. First item\n2. Second item")
                        .font(.custom(fontFamily, size: CGFloat(fontSize)))
                        .foregroundStyle(.secondary)

                    Text("> Blockquote text here")
                        .font(.custom(fontFamily, size: CGFloat(fontSize)))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(Color.accentColor.opacity(0.4))
                                .frame(width: 3)
                        }

                    Text("```swift\nlet x = 42\n```")
                        .font(.custom(fontFamily, size: CGFloat(fontSize * 0.9)))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .lineSpacing(CGFloat(lineHeight - 1) * CGFloat(fontSize))
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Preview

struct PreviewSettingsPane: View {
    var body: some View {
        Form {
            Section("Rendering") {
                LabeledContent("Mermaid Diagrams", value: "Enabled")
                LabeledContent("LaTeX Math (KaTeX)", value: "Enabled")
                LabeledContent("Code Highlighting", value: "30+ languages")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - PDF

struct PDFPaperSize: Identifiable, Equatable {
    let id: String
    let name: String
    let size: CGSize

    var label: String {
        "\(name) (\(Int(size.width)) x \(Int(size.height)) pt)"
    }

    static let a4ID = "a4"

    static let all: [PDFPaperSize] = [
        PDFPaperSize(id: "a0", name: "A0", size: CGSize(width: 2384, height: 3370)),
        PDFPaperSize(id: "a1", name: "A1", size: CGSize(width: 1684, height: 2384)),
        PDFPaperSize(id: "a2", name: "A2", size: CGSize(width: 1191, height: 1684)),
        PDFPaperSize(id: "a3", name: "A3", size: CGSize(width: 842, height: 1191)),
        PDFPaperSize(id: a4ID, name: "A4", size: CGSize(width: 595, height: 842)),
        PDFPaperSize(id: "a5", name: "A5", size: CGSize(width: 420, height: 595)),
        PDFPaperSize(id: "a6", name: "A6", size: CGSize(width: 298, height: 420)),
        PDFPaperSize(id: "b4", name: "B4", size: CGSize(width: 729, height: 1032)),
        PDFPaperSize(id: "b5", name: "B5", size: CGSize(width: 516, height: 729)),
        PDFPaperSize(id: "letter", name: "Letter", size: CGSize(width: 612, height: 792)),
        PDFPaperSize(id: "legal", name: "Legal", size: CGSize(width: 612, height: 1008)),
        PDFPaperSize(id: "tabloid", name: "Tabloid", size: CGSize(width: 792, height: 1224)),
        PDFPaperSize(id: "ledger", name: "Ledger", size: CGSize(width: 1224, height: 792)),
        PDFPaperSize(id: "executive", name: "Executive", size: CGSize(width: 522, height: 756)),
        PDFPaperSize(id: "statement", name: "Statement", size: CGSize(width: 396, height: 612)),
        PDFPaperSize(id: "folio", name: "Folio", size: CGSize(width: 612, height: 936))
    ]

    static func size(for id: String) -> CGSize {
        all.first(where: { $0.id == id })?.size
            ?? all.first(where: { $0.id == a4ID })?.size
            ?? CGSize(width: 595, height: 842)
    }

    static func label(for id: String) -> String {
        all.first(where: { $0.id == id })?.label ?? "A4 (595 x 842 pt)"
    }
}

struct PDFSettingsPane: View {
    @AppStorage("pdfHeaderText") private var headerText = ""
    @AppStorage("pdfHeaderAlign") private var headerAlign = 1
    @AppStorage("pdfFooterText") private var footerText = ""
    @AppStorage("pdfFooterAlign") private var footerAlign = 1
    @AppStorage("pdfPaperSize") private var paperSizeID = PDFPaperSize.a4ID
    @AppStorage("pdfFontFamily") private var fontFamily = "Georgia"
    @AppStorage("pdfFontSize") private var fontSize: Double = 11
    @AppStorage("pdfLineHeight") private var lineHeight: Double = 1.65

    private let allFamilies = NSFontManager.shared.availableFontFamilies

    var body: some View {
        Form {
            Section("Header") {
                TextField("", text: $headerText, prompt: Text("{file_name}"))
                Picker("Alignment", selection: $headerAlign) {
                    Text("Left").tag(0)
                    Text("Center").tag(1)
                    Text("Right").tag(2)
                }
                .pickerStyle(.segmented)
            }

            Section("Footer") {
                TextField("", text: $footerText, prompt: Text("Page {page_no}"))
                Picker("Alignment", selection: $footerAlign) {
                    Text("Left").tag(0)
                    Text("Center").tag(1)
                    Text("Right").tag(2)
                }
                .pickerStyle(.segmented)
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Placeholders")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("{page_no}  —  Page number")
                        .font(.caption).monospaced()
                    Text("{file_name}  —  File name without extension")
                        .font(.caption).monospaced()
                }
            }

            Section("Typography") {
                Picker("Family", selection: $fontFamily) {
                    ForEach(allFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                .pickerStyle(.menu)
                .onAppear {
                    if !allFamilies.contains(fontFamily) {
                        fontFamily = allFamilies.contains("Georgia") ? "Georgia" : (allFamilies.first ?? "Georgia")
                    }
                }

                HStack {
                    Text("Size")
                    Spacer()
                    TextField("", value: $fontSize, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 52)
                        .textFieldStyle(.roundedBorder)
                    Stepper("", value: $fontSize, in: 8...72, step: 1)
                        .labelsHidden()
                }

                HStack {
                    Text("Line Height")
                    Spacer()
                    TextField("", value: $lineHeight, format: .number.precision(.fractionLength(2)))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 52)
                        .textFieldStyle(.roundedBorder)
                    Stepper("", value: $lineHeight, in: 1.0...3.0, step: 0.05)
                        .labelsHidden()
                }

                Button("Reset to Defaults") {
                    fontFamily = allFamilies.contains("Georgia") ? "Georgia" : (allFamilies.first ?? "Georgia")
                    fontSize = 11
                    lineHeight = 1.65
                }
                .font(.callout)
            }

            Section("Export") {
                Picker("Paper Size", selection: $paperSizeID) {
                    ForEach(PDFPaperSize.all) { paperSize in
                        Text(paperSize.label).tag(paperSize.id)
                    }
                }
                .pickerStyle(.menu)
                .onAppear {
                    if !PDFPaperSize.all.contains(where: { $0.id == paperSizeID }) {
                        paperSizeID = PDFPaperSize.a4ID
                    }
                }
            }

            Section("Keyboard Shortcut") {
                Text("⇧⌘P")
                    .font(.monospaced(.callout)())
            }
        }
        .formStyle(.grouped)
    }
}
