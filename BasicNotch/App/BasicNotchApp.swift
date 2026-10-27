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

    static var active: [NSScreen] {
        let store = UserDefaults.standard
        let wanted = DisplaySelection.ids(available: NSScreen.screens.map(id), automatic: automatic.map(id),
            selected: store.integer(forKey: "notchDisplayID"), all: store.bool(forKey: "notchAllDisplays"))
        return NSScreen.screens.filter { wanted.contains(id(of: $0)) }
    }

    static func name(of screen: NSScreen) -> String {
        screen.safeAreaInsets.top > 0 ? "\(screen.localizedName) (notch)" : screen.localizedName
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let vm = NotchViewModel()
    private var displays: [Int: DisplayNotch] = [:]
    private var layoutSignature = ""
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var welcomeWindow: NSWindow?
    private var monitors: [Any] = []
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    private var hoverTimer: Timer?
    private var desktopBuddy: DesktopBuddyController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        vm.openSettings = { [weak self] in self?.showSettings() }
        vm.openGuide = { [weak self] in self?.openGuide() }
        layoutPanels()
        buildStatusItem()
        startMouseTracking()
        vm.start(startParty: false)
        desktopBuddy = DesktopBuddyController(vm: vm)
        if !UserDefaults.standard.bool(forKey: "hasSeenWelcome") { showWelcome() }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layoutPanels(force: true) }
        }
        // Follow the Screen setting.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.layoutPanels()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        desktopBuddy?.stop()
    }

    // MARK: - Panel

    private func layoutPanels(force: Bool = false) {
        let screens = NotchScreen.active
        let signature = screens.map { "\(NotchScreen.id(of: $0)):\($0.frame):\($0.visibleFrame):\($0.safeAreaInsets.top)" }.joined(separator: "|")
        guard force || signature != layoutSignature else { return }
        layoutSignature = signature
        let wanted = Set(screens.map(NotchScreen.id))
        for id in Array(displays.keys) where !wanted.contains(id) {
            displays.removeValue(forKey: id)?.close()
        }
        for screen in screens {
            let id = NotchScreen.id(of: screen)
            if let display = displays[id] { display.layout(on: screen) }
            else {
                let displayVM = NotchViewModel(shared: vm)
                displayVM.openSettings = vm.openSettings
                displayVM.openGuide = vm.openGuide
                let display = DisplayNotch(screen: screen, vm: displayVM)
                displays[id] = display
                displayVM.start(startServices: false)
            }
        }
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
        let dragBoard = NSPasteboard(name: .drag)
        if type == .leftMouseDown { dragChangeCount = dragBoard.changeCount }
        let draggingFiles = type == .leftMouseDragged && dragBoard.changeCount != dragChangeCount
            && (dragBoard.types?.contains(.fileURL) ?? false)
        for display in displays.values { display.handleMouse(at: NSEvent.mouseLocation, draggingFiles: draggingFiles) }
    }

    // MARK: - Menu bar item & settings

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "BasicNotch")
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Notch", action: #selector(openNotch), keyEquivalent: "").target = self
        if !PokeBrawlSprites.roster.isEmpty {
            menu.addItem(withTitle: "Respawn Pokémon", action: #selector(respawn), keyEquivalent: "r").target = self
        }
        let screens = NSMenuItem(title: "Show on Screen", action: nil, keyEquivalent: "")
        screens.submenu = NSMenu(title: "Show on Screen")
        screens.submenu?.delegate = self
        menu.addItem(screens)
        menu.addItem(withTitle: "Show / Hide Desktop Buddy", action: #selector(toggleBuddy), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Move to Next Screen", action: #selector(nextScreen), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Getting Started…", action: #selector(showWelcome), keyEquivalent: "").target = self
        menu.addItem(withTitle: "User Guide & Features…", action: #selector(openGuide), keyEquivalent: "?").target = self
        menu.addItem(withTitle: "About BasicNotch", action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit BasicNotch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func openGuide() {
        if let url = Bundle.main.url(forResource: "UserGuide", withExtension: "html") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func showAbout() { NSApp.orderFrontStandardAboutPanel(nil); NSApp.activate(ignoringOtherApps: true) }

    @objc private func showWelcome() {
        if welcomeWindow == nil {
            let root = WelcomeView(onGuide: { [weak self] in self?.openGuide() }, onStart: { [weak self] in
                UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
                self?.welcomeWindow?.close()
                self?.openNotch()
            })
            let window = NSWindow(contentViewController: NSHostingController(rootView: root))
            window.title = "Welcome to BasicNotch"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            welcomeWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        welcomeWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openNotch() {
        let point = NSEvent.mouseLocation
        let target = displays.values.first { $0.screen.frame.contains(point) } ?? displays.values.first
        target?.vm.isPinned = true
        target?.vm.open()
    }

    @objc private func toggleBuddy() {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: "desktopBuddyEnabled"), forKey: "desktopBuddyEnabled")
    }

    @objc private func respawn() { displays.values.forEach { $0.vm.party.respawnAll() } }

    // Rebuilt each time it opens, so plugged-in displays show up.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let current = UserDefaults.standard.integer(forKey: "notchDisplayID")
        let all = NSMenuItem(title: "All Connected Displays", action: #selector(chooseAllScreens), keyEquivalent: "")
        all.state = UserDefaults.standard.bool(forKey: "notchAllDisplays") ? .on : .off
        all.target = self
        menu.addItem(all)
        let allOn = UserDefaults.standard.bool(forKey: "notchAllDisplays")
        let auto = NSMenuItem(title: "Automatic", action: #selector(chooseScreen(_:)), keyEquivalent: "")
        auto.tag = 0
        auto.state = !allOn && current == 0 ? .on : .off
        auto.target = self
        menu.addItem(auto)
        menu.addItem(.separator())
        for screen in NSScreen.screens {
            let item = NSMenuItem(title: NotchScreen.name(of: screen), action: #selector(chooseScreen(_:)), keyEquivalent: "")
            item.tag = NotchScreen.id(of: screen)
            item.state = !allOn && current == item.tag ? .on : .off
            item.target = self
            menu.addItem(item)
        }
    }

    @objc private func chooseAllScreens() {
        UserDefaults.standard.set(true, forKey: "notchAllDisplays")
        layoutPanels()
    }

    @objc private func chooseScreen(_ sender: NSMenuItem) {
        UserDefaults.standard.set(false, forKey: "notchAllDisplays")
        UserDefaults.standard.set(sender.tag, forKey: "notchDisplayID")
        layoutPanels()
    }

    @objc private func nextScreen() {
        let screens = NSScreen.screens
        guard screens.count > 1, let current = NotchScreen.selected, let i = screens.firstIndex(of: current) else { return }
        UserDefaults.standard.set(false, forKey: "notchAllDisplays")
        UserDefaults.standard.set(NotchScreen.id(of: screens[(i + 1) % screens.count]), forKey: "notchDisplayID")
        layoutPanels()
    }

    @objc private func openSettingsAction() { showSettings() }

    private func showSettings() {
        for display in displays.values { display.vm.isPinned = false; display.vm.close() }
        if settingsWindow == nil {
            let root = SettingsView(onRespawn: { [weak self] in self?.respawn() }, tumblr: vm.tumblr)
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
