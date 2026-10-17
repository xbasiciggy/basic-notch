import AppKit

/// Notices camera cards (any volume with a DCIM folder), counts the photos and videos you haven't
/// imported yet, and copies them into ~/Pictures/Card Imports/<date>/ with live progress.
/// Imported files are remembered by name, size and date, so the same shots are never copied twice.
@MainActor
final class CardIngestService: ObservableObject {
    struct Card: Equatable {
        let volume: URL
        let name: String
        var total: Int
        var newFiles: [URL]
        var isScanning: Bool
    }

    struct Import: Equatable {
        let folder: URL
        let count: Int
        /// The JPEG/HEIC/PNG files, for sending on to Gallery Manager or Tumblr.
        let images: [URL]
    }

    @Published private(set) var card: Card?
    /// 0…1 while copying, nil otherwise.
    @Published private(set) var progress: Double?
    @Published private(set) var copiedCount = 0
    @Published private(set) var lastImport: Import?
    @Published var error: String?

    var onInsert: (Card) -> Void = { _ in }
    var onImported: (Import) -> Void = { _ in }

    nonisolated static let mediaExtensions: Set<String> = [
        "jpg", "jpeg", "heic", "heif", "png", "tif", "tiff",
        "dng", "cr2", "cr3", "nef", "nrw", "arw", "srf", "sr2", "raf", "orf", "rw2", "pef", "srw", "x3f", "3fr", "iiq",
        "mov", "mp4", "m4v", "mts", "avi",
    ]
    private static let viewableExtensions: Set<String> = ["jpg", "jpeg", "heic", "heif", "png"]

    private var observers: [NSObjectProtocol] = []
    private var copyTask: Task<Void, Never>?
    private var imported: Set<String> = CardIngestService.loadRegistry()

    var destinationRoot: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0].appendingPathComponent("Card Imports", isDirectory: true)
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] note in
            guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            MainActor.assumeIsolated { self?.consider(url, announce: true) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] note in
            guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            MainActor.assumeIsolated {
                guard let self, self.card?.volume.standardizedFileURL == url.standardizedFileURL else { return }
                self.copyTask?.cancel()
                self.card = nil
                self.progress = nil
            }
        })
        // A card that was already in when BasicNotch started.
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        for volume in volumes where volume.path.hasPrefix("/Volumes/") { consider(volume, announce: false) }
    }

    // MARK: Scanning

    private func consider(_ volume: URL, announce: Bool) {
        var isDir: ObjCBool = false
        let dcim = volume.appendingPathComponent("DCIM")
        guard FileManager.default.fileExists(atPath: dcim.path, isDirectory: &isDir), isDir.boolValue else { return }
        let name = (try? volume.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? volume.lastPathComponent
        card = Card(volume: volume, name: name, total: 0, newFiles: [], isScanning: true)
        lastImport = nil
        error = nil
        let known = imported
        Task {
            let (all, fresh) = await Task.detached(priority: .userInitiated) { Self.scan(dcim, known: known) }.value
            guard var current = self.card, current.volume == volume else { return }
            current.total = all
            current.newFiles = fresh
            current.isScanning = false
            self.card = current
            if announce { self.onInsert(current) }
        }
    }

    nonisolated private static func scan(_ dcim: URL, known: Set<String>) -> (Int, [URL]) {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: dcim, includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles]) else { return (0, []) }
        var total = 0
        var fresh: [URL] = []
        for case let url as URL in walker where mediaExtensions.contains(url.pathExtension.lowercased()) {
            total += 1
            if !known.contains(fingerprint(url)) { fresh.append(url) }
        }
        return (total, fresh.sorted { $0.lastPathComponent < $1.lastPathComponent })
    }

    nonisolated private static func fingerprint(_ url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let date = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(url.lastPathComponent)|\(values?.fileSize ?? 0)|\(Int(date))"
    }

    // MARK: Importing

    func importNew() {
        guard let card, !card.newFiles.isEmpty, progress == nil else { return }
        let files = card.newFiles
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let folder = destinationRoot.appendingPathComponent(formatter.string(from: Date()), isDirectory: true)
        progress = 0
        copiedCount = 0
        error = nil

        copyTask = Task {
            let total = files.count
            var copied: [URL] = []
            var copiedSources: Set<URL> = []
            var fingerprints: [String] = []
            for (i, source) in files.enumerated() {
                if Task.isCancelled { break }
                let result = await Task.detached(priority: .userInitiated) { () -> Result<(URL, String), Error> in
                    do {
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        let target = Self.uniqueURL(for: source.lastPathComponent, in: folder)
                        try FileManager.default.copyItem(at: source, to: target)
                        return .success((target, Self.fingerprint(source)))
                    } catch {
                        return .failure(error)
                    }
                }.value
                switch result {
                case .success(let (target, print)):
                    copied.append(target)
                    copiedSources.insert(source)
                    fingerprints.append(print)
                case .failure(let error):
                    self.error = "Couldn't copy \(source.lastPathComponent): \(error.localizedDescription)"
                }
                self.copiedCount = i + 1
                self.progress = Double(i + 1) / Double(total)
            }

            self.imported.formUnion(fingerprints)
            Self.saveRegistry(self.imported)
            let images = copied.filter { Self.viewableExtensions.contains($0.pathExtension.lowercased()) }
            let result = Import(folder: folder, count: copied.count, images: images)
            self.lastImport = result
            self.progress = nil
            if var current = self.card {
                current.newFiles.removeAll(where: copiedSources.contains)
                self.card = current
            }
            if !copied.isEmpty { self.onImported(result) }
        }
    }

    func cancelImport() { copyTask?.cancel() }

    func eject() {
        guard let card, progress == nil else { return }
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: card.volume)
        } catch {
            self.error = "Couldn't eject \(card.name): \(error.localizedDescription)"
        }
    }

    func revealLastImport() {
        guard let folder = lastImport?.folder else { return }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    nonisolated private static func uniqueURL(for name: String, in folder: URL) -> URL {
        var candidate = folder.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base)-\(n).\(ext)")
            n += 1
        }
        return candidate
    }

    // MARK: Registry of imported files

    private static var registryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BasicNotch/imported-card-files.json")
    }

    private static func loadRegistry() -> Set<String> {
        guard let data = try? Data(contentsOf: registryURL),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(list)
    }

    private static func saveRegistry(_ set: Set<String>) {
        try? FileManager.default.createDirectory(at: registryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(Array(set)).write(to: registryURL, options: .atomic)
    }
}
