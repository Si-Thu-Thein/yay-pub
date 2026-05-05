//
//  ContentView.swift
//  Yay
//
//  Created by Saturngod on 8/27/25.
//
import SwiftUI
import AppKit

struct ContentView: View {
    var body: some View {
        Text("Welcome to Yay")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct WindowTitleAccessor: NSViewRepresentable {
    let title: String
    let representedURL: URL?
    let isEdited: Bool
    let onURLChange: (URL?) -> Void

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.title = title
            window.representedURL = representedURL
            window.isDocumentEdited = isEdited
            window.titleVisibility = NSWindow.TitleVisibility.visible
            window.subtitle = ""

            // Observe representedURL changes (rename/move from title bar)
            if context.coordinator.observedWindow !== window {
                context.coordinator.observation = nil
                context.coordinator.observedWindow = window
                context.coordinator.observation = window.observe(\.representedURL, options: [.new]) { _, change in
                    DispatchQueue.main.async {
                        onURLChange(change.newValue ?? nil)
                    }
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var observation: NSKeyValueObservation?
        weak var observedWindow: NSWindow?
    }
}

#Preview {
    ContentView()
}
