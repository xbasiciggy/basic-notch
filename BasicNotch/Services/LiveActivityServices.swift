import AppKit
import Combine

/// Downloads and AirDrops arriving in ~/Downloads, using the same file progress that Finder's
/// progress bars use (Safari, Chrome and AirDrop all publish it).
@MainActor
final class DownloadMonitor: ObservableObject {
    struct Item: Identifiable, Equatable {
        let id: ObjectIdentifier
        let name: String
        let isAirDrop: Bool
        var fraction: Double
    }

    @Published private(set) var items: [Item] = []
    var onFinish: (_ name: String, _ isAirDrop: Bool) -> Void = { _, _ in }

    private var subscriber: Any?
    private var tracked: [ObjectIdentifier: Progress] = [:]
    private var poll: Timer?

    /// The busiest transfer, for the closed notch.
    var current: Item? { items.max { $0.fraction > $1.fraction } }
    var overallFraction: Double { items.isEmpty ? 0 : items.map(\.fraction).reduce(0, +) / Double(items.count) }

    func start() {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        subscriber = Progress.addSubscriber(forFileURL: downloads) { [weak self] progress in
            let id = ObjectIdentifier(progress)
            MainActor.assumeIsolated { self?.track(progress, id: id) }
            return { [weak self] in
                MainActor.assumeIsolated { self?.untrack(id) }
            }
        }
        poll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func track(_ progress: Progress, id: ObjectIdentifier) {
        tracked[id] = progress
        refresh()
    }

    private func untrack(_ id: ObjectIdentifier) {
        guard let progress = tracked.removeValue(forKey: id) else { return }
        let item = makeItem(progress, id: id)
        items.removeAll { $0.id == id }
        if !progress.isCancelled && (progress.isFinished || progress.fractionCompleted > 0.98) {
            onFinish(item.name, item.isAirDrop)
        }
    }

    private func refresh() {
        let fresh = tracked.map { makeItem($0.value, id: $0.key) }.sorted { $0.name < $1.name }
        if fresh != items { items = fresh }
    }

    private func makeItem(_ progress: Progress, id: ObjectIdentifier) -> Item {
        let url = progress.fileURL ?? (progress.userInfo[.fileURLKey] as? URL)
        var name = url?.lastPathComponent ?? "Download"
        for suffix in [".download", ".crdownload", ".part"] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
        }
        return Item(id: id, name: name, isAirDrop: progress.fileOperationKind == .receiving,
                    fraction: min(max(progress.fractionCompleted, 0), 1))
    }
}

/// Best-effort screen recording indicator: while the built-in recorder (Screenshot toolbar or
/// QuickTime) is recording, macOS puts a Stop button in the menu bar owned by "screencaptureui".
@MainActor
final class ScreenRecordingMonitor: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var startedAt: Date?
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    private func check() {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let statusLayer = Int(CGWindowLevelForKey(.statusWindow))
        let recording = windows.contains { info in
            (info[kCGWindowOwnerName as String] as? String) == "screencaptureui"
                && (info[kCGWindowLayer as String] as? Int) == statusLayer
        }
        if recording != isRecording {
            isRecording = recording
            startedAt = recording ? Date() : nil
        }
    }
}

/// Publishes the end of golden hour while it's on, so the closed notch can count down to sunset.
@MainActor
final class GoldenHourClock: ObservableObject {
    @Published private(set) var sunset: Date?
    private var timer: Timer?
    private var nextSunset: () -> Date? = { nil }

    var isActive: Bool { sunset != nil }

    func start(sunset provider: @escaping () -> Date?) {
        nextSunset = provider
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    func check() {
        let now = Date()
        let active = nextSunset().flatMap { set in now >= set.addingTimeInterval(-3600) && now < set ? set : nil }
        if active != sunset { sunset = active }
    }
}
