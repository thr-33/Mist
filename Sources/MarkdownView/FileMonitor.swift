import Foundation

/// Watches a file for content changes using DispatchSource.
public final class FileMonitor: @unchecked Sendable {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let queue = DispatchQueue(label: "com.markdownview.filemonitor")
    private var path: String?

    public var onChange: (() -> Void)?

    public init() {}

    deinit {
        stop()
    }

    public func watch(url: URL) {
        stop()
        path = url.path
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .rename, .delete, .attrib],
            queue: queue
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = src.data
            // Re-arm after rename/delete (editors often atomic-replace)
            if flags.contains(.rename) || flags.contains(.delete) {
                let path = self.path
                DispatchQueue.main.async {
                    self.onChange?()
                }
                if let path {
                    self.queue.async {
                        self.rewatch(path: path)
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.onChange?()
                }
            }
        }
        src.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
            }
            self?.fileDescriptor = -1
        }
        source = src
        src.resume()
    }

    public func stop() {
        source?.cancel()
        source = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    private func rewatch(path: String) {
        stop()
        // Brief delay for atomic save to finish
        queue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                self.watch(url: url)
            }
        }
    }
}
