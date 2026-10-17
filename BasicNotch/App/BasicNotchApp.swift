import SwiftUI
import AppKit

@main
struct BasicNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

/// Borderless panel that floats over the menu bar and can take clicks without activating the app.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// macOS normally shoves windows below the menu bar; the notch panel has to sit flush with the top edge.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Which display the notch lives on. "notchDisplayID" = 0 means automatic (the built-in notched screen).
enum NotchScreen {
    static func id(of screen: NSScreen) -> Int {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue ?? 0
    }

    static var automatic: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    static var selected: NSScreen? {
        let wanted = UserDefaults.standard.integer(forKey: "notchDisplayID")
        return NSScreen.screens.first { wanted != 0 && id(of: $0) == wanted } ?? automatic
    }

    static func name(of screen: NSScreen) -> String {
        screen.safeAreaInsets.top > 0 ? "\(screen.localizedName) (notch)" : screen.localizedName
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let vm = NotchViewModel()
    private var panel: NotchPanel?
    private var screen: NSScreen?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var monitors: [Any] = []
    private var closeTask: Task<Void, Never>?
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    private var hoverStart: Date?
    private var hoverTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        vm.openSettings = { [weak self] in self?.showSettings() }
        layoutPanel()
        buildStatusItem()
        startMouseTracking()
        vm.start()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layoutPanel() }
        }
        // Follow the Screen setting.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let wanted = NotchScreen.selected, wanted != self.screen else { return }
                self.layoutPanel()
            }
        }
    }

    // MARK: - Panel

    private func layoutPanel() {
        guard let screen = NotchScreen.selected else { return }
        self.screen = screen

        let topInset = screen.safeAreaInsets.top
        if topInset > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            vm.notchSize = CGSize(width: screen.frame.width - left.width - right.width, height: topInset)
            vm.hasNotch = true
        } else {
            // No camera housing: draw a notch the height of this screen's menu bar.
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            vm.notchSize = CGSize(width: 190, height: menuBar > 10 ? menuBar : max(NSStatusBar.system.thickness, 28))
            vm.hasNotch = false
        }

        let size = CGSize(width: vm.expandedSize.width + 80, height: vm.expandedSize.height + 60)
        let frame = NSRect(x: screen.frame.midX - size.width / 2,
                           y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)

        if panel == nil {
            let panel = NotchPanel(contentRect: frame,
                                   styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isMovable = false
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            panel.ignoresMouseEvents = true

            let hosting = NotchHostingView(rootView: NotchRootView(vm: vm))
            hosting.sizingOptions = []
            panel.contentView = hosting
            panel.orderFrontRegardless()
            self.panel = panel
        }
        panel?.setFrame(frame, display: true)
    }

    /// A rect hugging the top-center of the screen, in screen coordinates.
    private func topRect(_ size: CGSize) -> NSRect {
        guard let s = screen else { return .zero }
        return NSRect(x: s.frame.midX - size.width / 2, y: s.frame.maxY - size.height,
                      width: size.width, height: size.height + 4)
    }

    // MARK: - Hover / drag tracking

    private func startMouseTracking() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handleMouse(type) }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handleMouse(type) }
            return event
        }) { monitors.append(local) }

        // Event monitors can miss moves (e.g. over full-screen apps), so also check the cursor 30× a second.
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMouse(.mouseMoved) }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    private func handleMouse(_ type: NSEvent.EventType) {
        guard let panel else { return }
        let point = NSEvent.mouseLocation
        let dragBoard = NSPasteboard(name: .drag)
        if type == .leftMouseDown { dragChangeCount = dragBoard.changeCount }
        let draggingFiles = type == .leftMouseDragged
            && dragBoard.changeCount != dragChangeCount
            && (dragBoard.types?.contains(.fileURL) ?? false)

        if vm.isOpen {
            let inside = topRect(vm.expandedSize).insetBy(dx: -8, dy: -8).contains(point)
            panel.ignoresMouseEvents = !inside
            if let s = screen, inside {
                // Cursor in the open notch's coordinates (origin at its top-left), for the neon glow.
                vm.cursor.update(CGPoint(x: point.x - (s.frame.midX - vm.expandedSize.width / 2),
                                         y: s.frame.maxY - point.y))
            } else {
                vm.cursor.update(nil)
            }
            if inside || vm.keepsOpen {
                closeTask?.cancel()
                closeTask = nil
            } else if closeTask == nil {
                closeTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(300))
                    guard let self, !Task.isCancelled else { return }
                    self.vm.close()
                    self.closeTask = nil
                }
            }
        } else {
            vm.cursor.update(nil)
            let d = UserDefaults.standard
            let closed = vm.closedSize(wingWidth: d.double(forKey: "wingWidth"),
                                       showPokemon: d.bool(forKey: "showPokemon"),
                                       musicLiveActivity: d.bool(forKey: "musicLiveActivity"))
            // Hovering anywhere on the bar (notch + wings) opens it, after a short pause so
            // sweeping the cursor across the menu bar doesn't pop it open.
            let hoverRect = topRect(CGSize(width: max(closed.width, vm.notchSize.width + 16),
                                           height: vm.notchSize.height + 4))
            let hovering = hoverRect.contains(point)
            panel.ignoresMouseEvents = !hovering
            if hovering {
                let start = hoverStart ?? Date()
                hoverStart = start
                if draggingFiles || Date().timeIntervalSince(start) >= 0.12 {
                    if draggingFiles { vm.tab = .files }
                    hoverStart = nil
                    vm.open()
                }
            } else {
                hoverStart = nil
            }
        }
    }

    // MARK: - Menu bar item & settings

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "BasicNotch")
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Notch", action: #selector(openNotch), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Respawn Pokémon", action: #selector(respawn), keyEquivalent: "r").target = self
        let screens = NSMenuItem(title: "Show on Screen", action: nil, keyEquivalent: "")
        screens.submenu = NSMenu(title: "Show on Screen")
        screens.submenu?.delegate = self
        menu.addItem(screens)
        menu.addItem(withTitle: "Move to Next Screen", action: #selector(nextScreen), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit BasicNotch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func openNotch() {
        vm.isPinned = true
        vm.open()
    }

    @objc private func respawn() { vm.party.respawnAll() }

    // Rebuilt each time it opens, so plugged-in displays show up.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let current = UserDefaults.standard.integer(forKey: "notchDisplayID")
        let auto = NSMenuItem(title: "Automatic", action: #selector(chooseScreen(_:)), keyEquivalent: "")
        auto.tag = 0
        auto.state = current == 0 ? .on : .off
        auto.target = self
        menu.addItem(auto)
        menu.addItem(.separator())
        for screen in NSScreen.screens {
            let item = NSMenuItem(title: NotchScreen.name(of: screen), action: #selector(chooseScreen(_:)), keyEquivalent: "")
            item.tag = NotchScreen.id(of: screen)
            item.state = current == item.tag ? .on : .off
            item.target = self
            menu.addItem(item)
        }
    }

    @objc private func chooseScreen(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag, forKey: "notchDisplayID")
        layoutPanel()
    }

    @objc private func nextScreen() {
        let screens = NSScreen.screens
        guard screens.count > 1, let current = screen, let i = screens.firstIndex(of: current) else { return }
        UserDefaults.standard.set(NotchScreen.id(of: screens[(i + 1) % screens.count]), forKey: "notchDisplayID")
        layoutPanel()
    }

    @objc private func openSettingsAction() { showSettings() }

    private func showSettings() {
        vm.isPinned = false
        vm.close()
        if settingsWindow == nil {
            let root = SettingsView(onRespawn: { [weak self] in self?.vm.party.respawnAll() }, tumblr: vm.tumblr)
            let window = NSWindow(contentViewController: NSHostingController(rootView: root))
            window.title = "BasicNotch Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
