import SwiftUI

@main
struct YayiPadApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownFileDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
        }
    }
}
