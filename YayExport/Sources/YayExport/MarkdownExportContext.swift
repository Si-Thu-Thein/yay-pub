#if os(macOS)
import AppKit
import SwiftUI

public struct MarkdownExportContext: Equatable {
    public let text: String
    public let suggestedFilename: String
    public let fileURL: URL?

    public init(text: String, suggestedFilename: String, fileURL: URL? = nil) {
        self.text = text
        self.suggestedFilename = suggestedFilename
        self.fileURL = fileURL
    }
}

@MainActor
public final class WindowExportContextRegistry: ObservableObject {
    public static let shared = WindowExportContextRegistry()

    private final class Box: NSObject {
        let context: MarkdownExportContext

        init(_ context: MarkdownExportContext) {
            self.context = context
        }
    }

    private let contexts = NSMapTable<NSWindow, Box>(keyOptions: .weakMemory, valueOptions: .strongMemory)
    private var observers: [NSObjectProtocol] = []

    private init() {
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didResignMainNotification
        ]

        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public func set(_ context: MarkdownExportContext?, for window: NSWindow) {
        if let context {
            contexts.setObject(Box(context), forKey: window)
        } else {
            contexts.removeObject(forKey: window)
        }
        objectWillChange.send()
    }

    public func context(for window: NSWindow?) -> MarkdownExportContext? {
        guard let window else { return nil }
        return contexts.object(forKey: window)?.context
    }

    public func currentContext() -> MarkdownExportContext? {
        context(for: NSApp.keyWindow) ?? context(for: NSApp.mainWindow)
    }
}

public struct WindowExportContextWriter: NSViewRepresentable {
    public let context: MarkdownExportContext?

    public init(context: MarkdownExportContext?) {
        self.context = context
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeNSView(context: Context) -> NSView {
        NSView()
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            WindowExportContextRegistry.shared.set(self.context, for: window)

            if context.coordinator.observedWindow !== window {
                context.coordinator.teardown()
                context.coordinator.observedWindow = window
                context.coordinator.closeObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { _ in
                    Task { @MainActor in
                        WindowExportContextRegistry.shared.set(nil, for: window)
                    }
                }
            }
        }
    }

    public final class Coordinator {
        public weak var observedWindow: NSWindow?
        public var closeObserver: NSObjectProtocol?

        public init() {}

        deinit {
            teardown()
        }

        public func teardown() {
            if let closeObserver {
                NotificationCenter.default.removeObserver(closeObserver)
            }
            closeObserver = nil
            observedWindow = nil
        }
    }
}

private struct MarkdownExportContextKey: FocusedValueKey {
    typealias Value = MarkdownExportContext
}

public extension FocusedValues {
    var markdownExport: MarkdownExportContext? {
        get { self[MarkdownExportContextKey.self] }
        set { self[MarkdownExportContextKey.self] = newValue }
    }
}

#endif
