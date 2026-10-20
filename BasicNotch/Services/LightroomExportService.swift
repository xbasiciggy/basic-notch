import AppKit
import Combine

/// Versioned, local-only snapshots written by the Lightroom Classic export action.
struct LightroomExportJob: Codable, Equatable, Identifiable {
    enum State: String, Codable { case running, completed, failed, cancelled, interrupted }
    let version: Int
    let id: String
    var state: State
    let total: Int
    let completed: Int
    let failed: Int
    let startedAt: Double
    let updatedAt: Double
    let currentFile: String?
    let outputFolder: String?
    let message: String?

    var processed: Int { completed + failed }
    var progress: Double { total > 0 ? min(1, Double(processed) / Double(total)) : 0 }
    var title: String {
        switch state {
        case .running: return "Exporting from Lightroom"
        case .completed: return "Lightroom rendering finished"
        case .failed: return "Lightroom export had errors"
        case .cancelled: return "Lightroom export stopped"
        case .interrupted: return "Lightroom connection lost"
        }
    }

    func validated(now: Date) -> Self? {
        let time = now.timeIntervalSince1970
        guard version == 1, !id.isEmpty, id.count <= 80,
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
              total >= 0, total <= 1_000_000, completed >= 0, failed >= 0,
              completed <= total, failed <= total - completed,
              startedAt.isFinite, updatedAt.isFinite,
              startedAt > 0, updatedAt >= startedAt, updatedAt <= time + 60,
              time - updatedAt < 7 * 86400,
              [currentFile, outputFolder, message].compactMap({ $0 }).allSatisfy({ $0.count <= 4096 }),
              outputFolder.map({ $0.hasPrefix("/") && !$0.contains("\0") }) ?? true else { return nil }
        guard state != .completed || (processed == total && failed == 0) else { return nil }
        var result = self
        if state == .running && time - updatedAt > 45 { result.state = .interrupted }
        return result
    }
}

@MainActor
final class LightroomExportService: ObservableObject {
    @Published private(set) var jobs: [LightroomExportJob] = []
    @Published var setupError: String?
    var onFinish: (LightroomExportJob) -> Void = { _ in }
    private var loop: Task<Void, Never>?
    private var announced = Set<String>()
    private var observedRunning = Set<String>()
    private var dismissed = Set<String>()
    private let started = Date()
    let folder: URL

    init(folder: URL? = nil) {
        self.folder = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BasicNotch/LightroomExports", isDirectory: true)
    }

    var active: [LightroomExportJob] { jobs.filter { $0.state == .running } }
    var current: LightroomExportJob? { active.first }
    var progress: Double {
        let total = active.reduce(0) { $0 + $1.total }
        return total > 0 ? Double(active.reduce(0) { $0 + $1.processed }) / Double(total) : 0
    }
    var countLabel: String {
        "\(active.reduce(0) { $0 + $1.processed })/\(active.reduce(0) { $0 + $1.total })"
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let folder = self?.folder else { return }
                let found = await Task.detached(priority: .utility) { Self.readJobs(in: folder, now: Date()) }.value
                guard !Task.isCancelled else { return }
                self?.accept(found)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    static nonisolated func readJobs(in folder: URL, now: Date) -> [LightroomExportJob] {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { return [] }
        let candidates = urls.filter { $0.pathExtension == "plist" }.compactMap { url -> (URL, Date)? in
            guard let info = try? url.resourceValues(forKeys: keys), info.isSymbolicLink != true,
                  let size = info.fileSize, size > 0, size <= 65536 else { return nil }
            return (url, info.contentModificationDate ?? .distantPast)
        }.sorted { $0.1 > $1.1 }.prefix(128)
        var latest: [String: LightroomExportJob] = [:]
        for (url, _) in candidates {
            guard let data = try? Data(contentsOf: url), data.count <= 65536,
                  let parsed = try? PropertyListDecoder().decode(LightroomExportJob.self, from: data),
                  let job = parsed.validated(now: now) else { continue }
            if latest[job.id].map({ $0.updatedAt >= job.updatedAt }) != true { latest[job.id] = job }
        }
        return latest.values.sorted { $0.startedAt > $1.startedAt }
    }

    func accept(_ found: [LightroomExportJob]) {
        for job in found where job.state == .running { observedRunning.insert(job.id) }
        for job in found where job.state != .running && job.state != .interrupted {
            if (observedRunning.contains(job.id) || job.startedAt >= started.timeIntervalSince1970 - 2), announced.insert(job.id).inserted { onFinish(job) }
        }
        let visible = Array(found.filter { !dismissed.contains($0.id) }.prefix(24))
        if jobs != visible { jobs = visible }
    }

    func clearFinished() {
        for job in jobs where job.state != .running { dismissed.insert(job.id) }
        jobs.removeAll { $0.state != .running }
    }

    func reveal(_ job: LightroomExportJob) {
        guard let path = job.outputFolder else { return }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else { setupError = "That export folder is no longer available."; return }
        NSWorkspace.shared.open(url)
    }

    func savePlugin() {
        guard let source = Bundle.main.url(forResource: "Lightroom", withExtension: "bundle")?
            .appendingPathComponent("BasicNotchExport.lrplugin"), FileManager.default.fileExists(atPath: source.path) else {
            setupError = "The Lightroom companion plug-in is missing from this app."; return
        }
        let panel = NSOpenPanel()
        panel.title = "Choose where to save the Lightroom Classic plug-in"
        panel.prompt = "Save Plug-in"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let target = folder.appendingPathComponent("BasicNotchExport.lrplugin", isDirectory: true)
        guard !FileManager.default.fileExists(atPath: target.path) else { setupError = "A plug-in already exists in that folder. Choose another folder to save this copy."; return }
        do {
            try FileManager.default.copyItem(at: source, to: target)
            setupError = nil
            NSWorkspace.shared.activateFileViewerSelecting([target])
        } catch { setupError = "Could not save the plug-in: \(error.localizedDescription)" }
    }
}
