import AppKit
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popoverController: PopoverController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        refreshIcon()

        popoverController = PopoverController()
        HotkeyController.install()

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleMuteChanged), name: .muteStateChanged, object: nil)
    }

    // MARK: Status icon

    @objc private func refreshIcon() {
        let muted = AudioController.shared.currentMuted()
        let symbol = muted ? "mic.slash.fill" : "mic.fill"
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: muted ? "Muted" : "Unmuted")
        img?.isTemplate = !muted
        statusItem.button?.image = img
        statusItem.button?.contentTintColor = muted ? .systemRed : nil
    }

    @objc private func handleMuteChanged() {
        let muted = AudioController.shared.currentMuted()
        refreshIcon()
        HUDController.shared.flash(muted: muted)
        SoundController.shared.play(muted: muted)
    }

    // MARK: Click handling

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showRightClickMenu()
        } else {
            popoverController.toggle(relativeTo: sender)
        }
    }

    private func showRightClickMenu() {
        let menu = NSMenu()
        let toggle = NSMenuItem(title: "Toggle Mute", action: #selector(toggleMute), keyEquivalent: "")
        toggle.target = self
        if let s = KeyboardShortcuts.getShortcut(for: .toggleMute) {
            toggle.title = "Toggle Mute   " + s.description
        }
        menu.addItem(toggle)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit muteapp", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil  // detach so left-click goes back to action selector
    }

    @objc private func toggleMute() {
        AudioController.shared.toggle()
    }
}
