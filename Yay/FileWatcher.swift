import Foundation
import Combine

final class FileWatcher: ObservableObject {
    private var sources: [URL: DispatchSourceFileSystemObject] = [:]
    private let queue = DispatchQueue(label: "com.yay.filewatcher", qos: .utility)
    var onFileChanged: ((URL) -> Void)?

    func watch(_ url: URL) {
        guard sources[url] == nil else { return }
        startWatching(url)
    }

    func unwatch(_ url: URL) {
        guard let source = sources.removeValue(forKey: url) else { return }
        source.cancel()
    }

    func unwatchAll() {
        for (_, source) in sources {
            source.cancel()
        }
        sources.removeAll()
    }

    deinit {
        unwatchAll()
    }

    private func startWatching(_ url: URL) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let needsRewatch = source.data.contains(.delete) || source.data.contains(.rename)

            DispatchQueue.main.async {
                self.onFileChanged?(url)
            }

            if needsRewatch {
                source.cancel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let self, self.sources[url] != nil else { return }
                    self.sources.removeValue(forKey: url)
                    self.startWatching(url)
                }
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        sources[url] = source
    }
}
