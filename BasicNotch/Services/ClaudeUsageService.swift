import Foundation

/// Reads Claude Code's local session logs (~/.claude/projects/**/*.jsonl) and totals token usage
/// for the current 5-hour usage window, today and the last 7 days. Everything stays on this Mac.
@MainActor
final class ClaudeUsageService: ObservableObject {
    struct Snapshot {
        var blockTokens = 0
        var blockStart: Date?
        var blockEnd: Date?
        var todayTokens = 0
        var weekTokens = 0
        var weekMessages = 0
        var topModel = ""
        /// Biggest 5-hour window in the last week, used as the bar's 100% when no limit is set.
        var peakBlockTokens = 0
    }

    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var available = false

    private var loop: Task<Void, Never>?
    private let scanner = UsageScanner()

    func start() {
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    /// Fraction of the 5-hour window used, against the limit from Settings (or the recent peak).
    var fraction: Double {
        let limit = UserDefaults.standard.integer(forKey: "claudeBlockLimit")
        let reference = limit > 0 ? limit : max(snapshot.peakBlockTokens, 1)
        return min(Double(snapshot.blockTokens) / Double(reference), 1)
    }

    var isActive: Bool {
        guard let end = snapshot.blockEnd else { return false }
        return end > Date()
    }

    func refresh() async {
        let scanner = self.scanner
        let result = await Task.detached(priority: .utility) { scanner.scan() }.value
        snapshot = result.snapshot
        available = result.foundLogs
    }

    static func tokens(_ n: Int) -> String {
        switch n {
        case 1_000_000...: String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...: String(format: "%.0fK", Double(n) / 1_000)
        default: "\(n)"
        }
    }
}

/// Incremental JSONL reader: remembers how far into each log it has read, so rescans only parse new lines.
private final class UsageScanner: @unchecked Sendable {
    private struct Entry {
        let date: Date
        let tokens: Int
        let model: String
    }

    private var offsets: [URL: UInt64] = [:]
    private var entries: [String: Entry] = [:]  // keyed by message id + request id (logs repeat streamed messages)
    private let lock = NSLock()
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func scan() -> (snapshot: ClaudeUsageService.Snapshot, foundLogs: Bool) {
        lock.lock()
        defer { lock.unlock() }

        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            return (.init(), false)
        }
        var found = false
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            found = true
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            guard let modified = values?.contentModificationDate, modified > weekAgo else { continue }
            read(url, size: UInt64(values?.fileSize ?? 0))
        }

        entries = entries.filter { $0.value.date > weekAgo }
        return (summarize(), found)
    }

    private func read(_ url: URL, size: UInt64) {
        var offset = offsets[url] ?? 0
        if size < offset { offset = 0 }  // file was rewritten
        guard size > offset, let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return }

        // Only consume complete lines; a partial last line is picked up next time.
        guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return }
        let complete = data[data.startIndex...lastNewline]
        offsets[url] = offset + UInt64(complete.count)

        for line in complete.split(separator: UInt8(ascii: "\n")) where line.count > 20 {
            // Cheap filter before JSON parsing.
            guard line.range(of: Data("\"usage\"".utf8)) != nil,
                  let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let message = obj["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let stamp = obj["timestamp"] as? String,
                  let date = iso.date(from: stamp) else { continue }
            let count = { (key: String) in (usage[key] as? Int) ?? 0 }
            // Input + output + cache writes. Cache reads are excluded: they're cheap and would swamp the numbers.
            let tokens = count("input_tokens") + count("output_tokens") + count("cache_creation_input_tokens")
            let key = "\(message["id"] as? String ?? UUID().uuidString)|\(obj["requestId"] as? String ?? "")"
            entries[key] = Entry(date: date, tokens: tokens, model: message["model"] as? String ?? "")
        }
    }

    private func summarize() -> ClaudeUsageService.Snapshot {
        var snap = ClaudeUsageService.Snapshot()
        let sorted = entries.values.sorted { $0.date < $1.date }
        let startOfToday = Calendar.current.startOfDay(for: Date())
        var models: [String: Int] = [:]

        // 5-hour windows: a window starts at the top of the hour of the first message after the previous one ended.
        var blockStart: Date?
        var blockTokens = 0
        for e in sorted {
            if let start = blockStart, e.date < start.addingTimeInterval(5 * 3600) {
                blockTokens += e.tokens
            } else {
                if blockStart != nil { snap.peakBlockTokens = max(snap.peakBlockTokens, blockTokens) }
                let hour = Calendar.current.dateInterval(of: .hour, for: e.date)?.start ?? e.date
                blockStart = hour
                blockTokens = e.tokens
            }
            snap.weekTokens += e.tokens
            snap.weekMessages += 1
            if e.date >= startOfToday { snap.todayTokens += e.tokens }
            if !e.model.isEmpty, !e.model.hasPrefix("<") { models[e.model, default: 0] += e.tokens }
        }
        snap.peakBlockTokens = max(snap.peakBlockTokens, blockTokens)
        if let start = blockStart, start.addingTimeInterval(5 * 3600) > Date() {
            snap.blockStart = start
            snap.blockEnd = start.addingTimeInterval(5 * 3600)
            snap.blockTokens = blockTokens
        }
        snap.topModel = models.max { $0.value < $1.value }?.key ?? ""
        return snap
    }
}
