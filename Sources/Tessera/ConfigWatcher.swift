import Foundation

// Calls onChange when the config file's contents change. Editors often save by
// renaming a new file over the old one, which a watch on the file alone misses,
// so its folder is watched too, or the nearest existing one on a fresh install.
@MainActor
final class ConfigWatcher {
    var onChange: (() -> Void)?
    private let url: URL
    private var fileSource: DispatchSourceFileSystemObject?
    private var folderSource: DispatchSourceFileSystemObject?
    private var lastContents: Data?
    private var debounce: Task<Void, Never>?

    init(url: URL) { self.url = url }

    // The bytes the app last read, so only a later change counts.
    func noteContents(_ data: Data?) { lastContents = data }

    func start() { arm() }

    private func arm() {
        fileSource?.cancel()
        folderSource?.cancel()
        var folder = url.deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: folder.path), folder.path != "/" {
            folder = folder.deletingLastPathComponent()
        }
        folderSource = watch(folder.path, [.write])
        fileSource = watch(url.path, [.write, .extend, .delete, .rename])
    }

    private func watch(_ path: String, _ mask: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: mask, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.changed() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    // A save fires several events; read once they settle. Re-arming follows a
    // renamed-over file and a folder that has just been created.
    private func changed() {
        debounce?.cancel()
        debounce = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            self.arm()
            guard let contents = try? Data(contentsOf: self.url), contents != self.lastContents else { return }
            self.lastContents = contents
            self.onChange?()
        }
    }
}
