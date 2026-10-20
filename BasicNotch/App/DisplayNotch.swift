import SwiftUI
import AppKit

/// Independent hover/pin/geometry state for one screen; the view model shares app services.
@MainActor
final class DisplayNotch {
    let vm: NotchViewModel
    let panel: NotchPanel
    private(set) var screen: NSScreen
    private var closeTask: Task<Void, Never>?
    private var hoverStart: Date?

    init(screen: NSScreen, vm: NotchViewModel) {
        self.screen = screen
        self.vm = vm
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.isMovable = false; panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        let hosting = NotchHostingView(rootView: NotchRootView(vm: vm))
        hosting.sizingOptions = []
        panel.contentView = hosting
        layout(on: screen)
        panel.orderFrontRegardless()
    }

    func layout(on screen: NSScreen) {
        self.screen = screen
        let topInset = screen.safeAreaInsets.top
        if topInset > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            vm.notchSize = CGSize(width: screen.frame.width - left.width - right.width, height: topInset)
            vm.hasNotch = true
        } else {
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            vm.notchSize = CGSize(width: 190, height: menuBar > 10 ? menuBar : max(NSStatusBar.system.thickness, 28))
            vm.hasNotch = false
        }
        let size = CGSize(width: vm.expandedSize.width + 80, height: vm.expandedSize.height + 60)
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                              width: size.width, height: size.height), display: true)
    }

    private func topRect(_ size: CGSize) -> NSRect {
        NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height + 4)
    }

    func handleMouse(at point: NSPoint, draggingFiles: Bool) {
        if vm.isOpen {
            let inside = topRect(vm.expandedSize).insetBy(dx: -8, dy: -8).contains(point)
            panel.ignoresMouseEvents = !inside
            vm.cursor.update(inside ? CGPoint(x: point.x - (screen.frame.midX - vm.expandedSize.width / 2), y: screen.frame.maxY - point.y) : nil)
            if inside || vm.keepsOpen { closeTask?.cancel(); closeTask = nil }
            else if closeTask == nil {
                closeTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(300))
                    guard let self, !Task.isCancelled else { return }
                    self.vm.close(); self.closeTask = nil
                }
            }
        } else {
            vm.cursor.update(nil)
            let defaults = UserDefaults.standard
            let size = vm.closedSize(wingWidth: defaults.double(forKey: "wingWidth"), showPokemon: defaults.bool(forKey: "showPokemon"), musicLiveActivity: defaults.bool(forKey: "musicLiveActivity"))
            let hovering = topRect(CGSize(width: max(size.width, vm.notchSize.width + 16), height: vm.notchSize.height + 4)).contains(point)
            panel.ignoresMouseEvents = !hovering
            if hovering {
                let start = hoverStart ?? Date(); hoverStart = start
                if draggingFiles || Date().timeIntervalSince(start) >= 0.12 {
                    if draggingFiles { vm.tab = .files }
                    hoverStart = nil; vm.open()
                }
            } else { hoverStart = nil }
        }
    }

    func close() {
        closeTask?.cancel()
        vm.party.stop()
        panel.contentView = nil
        panel.close()
    }
}
