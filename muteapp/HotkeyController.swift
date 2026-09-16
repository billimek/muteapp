import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleMute = Self("toggleMute", initial: .init(.m, modifiers: [.control, .option, .command]))
}

@MainActor
enum HotkeyController {
    static func install() {
        KeyboardShortcuts.onKeyDown(for: .toggleMute) {
            AudioController.shared.toggle()
        }
    }
}
