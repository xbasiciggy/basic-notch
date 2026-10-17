import AppKit
import SwiftUI
import UniformTypeIdentifiers
import EventKit
import IOKit.ps
import AVFoundation

// MARK: - File shelf

@MainActor
final class FileTrayService: ObservableObject {
    @Published private(set) var files: [URL] = []
    /// Files picked (single click) for posting.
    @Published var selected: Set<URL> = []
    private let key = "trayFiles"

    static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension.lowercased())?.conforms(to: .image) ?? false
    }

    var images: [URL] { files.filter(Self.isImage) }

    /// Selected images, or every image on the shelf when none are selected.
    var imagesToPost: [URL] {
        let picked = images.filter(selected.contains)
        return picked.isEmpty ? images : picked
    }

    func toggleSelection(_ url: URL) {
        if selected.contains(url) { selected.remove(url) } else { selected.insert(url) }
    }

    init() {
        files = (UserDefaults.standard.stringArray(forKey: key) ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in self.insert(url) }
            }
        }
        return accepted
    }

    func insert(_ url: URL) {
        guard !files.contains(url) else { return }
        files.insert(url, at: 0)
        save()
    }

    func remove(_ url: URL) {
        selected.remove(url)
        files.removeAll { $0 == url }
        save()
    }

    func clear() {
        selected.removeAll()
        files.removeAll()
        save()
    }

    func open(_ url: URL) { NSWorkspace.shared.open(url) }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    func airDrop(_ urls: [URL]) {
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
    }

    private func save() {
        UserDefaults.standard.set(files.map(\.path), forKey: key)
    }
}

// MARK: - Calendar

@MainActor
final class CalendarService: ObservableObject {
    struct Event: Identifiable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let color: Color
    }

    @Published private(set) var next: Event?
    private let store = EKEventStore()
    private var loop: Task<Void, Never>?

    func start() {
        Task {
            guard (try? await store.requestFullAccessToEvents()) == true else { return }
            NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            loop = Task { [weak self] in
                while !Task.isCancelled {
                    self?.refresh()
                    try? await Task.sleep(for: .seconds(60))
                }
            }
        }
    }

    func refresh() {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(60 * 60 * 24), calendars: nil)
        let event = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .first
        next = event.map {
            Event(id: $0.eventIdentifier ?? UUID().uuidString,
                  title: $0.title ?? "Event",
                  start: $0.startDate,
                  end: $0.endDate,
                  color: Color(nsColor: $0.calendar.color))
        }
    }

    func openCalendarApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

// MARK: - Battery

@MainActor
final class BatteryService: ObservableObject {
    @Published private(set) var level = 100
    @Published private(set) var isCharging = false
    @Published private(set) var isPluggedIn = false
    @Published private(set) var hasBattery = false
    /// Briefly true after plugging in, to show the charging live activity in the closed notch.
    @Published private(set) var flash = false
    private var loop: Task<Void, Never>?
    private var didRead = false

    func start() {
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.read()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func read() {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let pluggedIn = desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue

            if didRead && pluggedIn && !isPluggedIn { showFlash() }
            hasBattery = true
            level = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current
            isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
            isPluggedIn = pluggedIn
            didRead = true
            return
        }
    }

    private func showFlash() {
        withAnimation(.spring) { flash = true }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            withAnimation(.spring) { self?.flash = false }
        }
    }
}

// MARK: - Camera mirror

final class CameraPreviewNSView: NSView {
    private let session = AVCaptureSession()
    private let previewLayer: AVCaptureVideoPreviewLayer

    override init(frame frameRect: NSRect) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted, let self else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                if self.session.inputs.isEmpty,
                   let device = AVCaptureDevice.default(for: .video),
                   let input = try? AVCaptureDeviceInput(device: device),
                   self.session.canAddInput(input) {
                    self.session.addInput(input)
                }
                self.session.startRunning()
            }
        }
    }

    func stop() {
        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
    }
}

struct CameraMirror: NSViewRepresentable {
    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView()
        view.start()
        return view
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {}

    static func dismantleNSView(_ nsView: CameraPreviewNSView, coordinator: ()) {
        nsView.stop()
    }
}
