import AppKit

/// Sends Shelf images to Gallery Manager (v1.3.76+), which imports them into a portfolio album.
/// Reads Gallery Manager's library read-only for the list of sections and albums, then drops a
/// request into its Inbox folder and pings it (launching it if needed).
@MainActor
final class GalleryManagerInbox: ObservableObject {
    struct Section: Identifiable, Hashable {
        let id: UUID
        let title: String
    }

    struct Album: Identifiable, Hashable {
        let id: UUID
        let title: String
        let sectionID: UUID?
        let photoCount: Int
        let cover: String?
    }

    static let bundleID = "org.opensource.gallerymanager"
    static let minimumVersion = "1.3.76"

    @Published private(set) var sections: [Section] = []
    @Published private(set) var albums: [Album] = []
    @Published private(set) var status: String?
    @Published var error: String?
    @Published var isComposing = false

    private let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("GalleryManager", isDirectory: true)

    func albums(in section: UUID?) -> [Album] { albums.filter { $0.sectionID == section } }

    // MARK: Library (read-only)

    private struct LibraryFile: Decodable {
        struct Nav: Decodable {
            let id: UUID
            let kind: String
            let title: String
            let order: Int?
            let visible: Bool?
        }
        struct GalleryEntry: Decodable {
            let id: UUID
            let title: String
            let navigationItemID: UUID?
            let sortOrder: Int?
            let photoPaths: [String]?
            let coverPhotoPath: String?
        }
        let galleries: [GalleryEntry]
        let navigationItems: [Nav]
    }

    func loadLibrary() {
        do {
            let data = try Data(contentsOf: root.appendingPathComponent("library.json"))
            let library = try JSONDecoder().decode(LibraryFile.self, from: data)
            sections = library.navigationItems
                .filter { $0.kind == "Gallery Category" }
                .sorted { ($0.order ?? 0) < ($1.order ?? 0) }
                .map { Section(id: $0.id, title: $0.title) }
            albums = library.galleries
                .sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
                .map { Album(id: $0.id, title: $0.title, sectionID: $0.navigationItemID,
                             photoCount: $0.photoPaths?.count ?? 0, cover: $0.coverPhotoPath) }
            error = nil
        } catch {
            sections = []
            albums = []
            self.error = "Couldn't read Gallery Manager's library — open Gallery Manager once first"
        }
    }

    // MARK: Sending

    /// Copies the images into a new Inbox request and wakes Gallery Manager.
    func send(_ images: [URL], toAlbum album: Album?, newAlbumTitle: String?, section: Section?) {
        guard !images.isEmpty else { return }
        error = nil
        let fm = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let folder = root.appendingPathComponent("Inbox/\(stamp)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            var names: [String] = []
            for (i, url) in images.enumerated() {
                let name = String(format: "%03d-%@", i + 1, url.lastPathComponent)
                try fm.copyItem(at: url, to: folder.appendingPathComponent(name))
                names.append(name)
            }
            var request: [String: Any] = ["version": 1, "files": names]
            if let album {
                request["galleryID"] = album.id.uuidString
            } else if let title = newAlbumTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                request["newGalleryTitle"] = title
                if let section { request["navigationItemID"] = section.id.uuidString }
            } else {
                throw NSError(domain: "BasicNotch", code: 1, userInfo: [NSLocalizedDescriptionKey: "Pick an album or name a new one"])
            }
            // Written last and atomically: Gallery Manager ignores folders until this exists.
            try JSONSerialization.data(withJSONObject: request, options: .prettyPrinted)
                .write(to: folder.appendingPathComponent("request.json"), options: .atomic)
        } catch {
            try? fm.removeItem(at: folder)
            self.error = error.localizedDescription
            return
        }

        let target = album?.title ?? newAlbumTitle ?? "album"
        status = "Sent \(images.count) photo\(images.count == 1 ? "" : "s") to \(target) — finish in Gallery Manager"
        wakeGalleryManager()
    }

    private func wakeGalleryManager() {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first {
            if let version = Self.version(of: running.bundleURL), Self.isOlder(version, than: Self.minimumVersion) {
                error = "The running Gallery Manager is v\(version). Open v\(Self.minimumVersion) or newer to import (your photos are waiting in its inbox)."
            }
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("org.opensource.gallerymanager.inbox"), object: nil, userInfo: nil, deliverImmediately: true)
            running.activate()
            return
        }
        // Not running: launch the newest installed copy (it imports the inbox on launch).
        let candidates = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: Self.bundleID)
        guard let newest = candidates.max(by: { Self.isOlder(Self.version(of: $0) ?? "0", than: Self.version(of: $1) ?? "0") }) else {
            error = "Gallery Manager isn't installed — your photos are waiting in its inbox"
            return
        }
        if let version = Self.version(of: newest), Self.isOlder(version, than: Self.minimumVersion) {
            error = "Newest Gallery Manager found is v\(version); build v\(Self.minimumVersion) to import"
        }
        NSWorkspace.shared.openApplication(at: newest, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func version(of app: URL?) -> String? {
        guard let app else { return nil }
        return Bundle(url: app)?.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    private static func isOlder(_ a: String, than b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedAscending
    }
}
