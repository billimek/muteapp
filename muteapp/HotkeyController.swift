import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleMute = Self("toggleMute", default: .init(.m, modifiers: [.control, .option, .command]))

    // Push-to-talk hotkey. Has no default; assigning it enables push-to-talk,
    // clearing it disables the mode.
    static let pushToTalk = Self("pushToTalk")
}

enum HotkeyController {
    // Tracks whether the push-to-talk key is currently held, so repeated
    // key-down events (key auto-repeat) don't re-trigger the unmute.
    private static var isTalking = false

    // Registers the global hotkey handlers.
    //
    // The toggle hotkey flips the mute state on key down. The push-to-talk
    // hotkey, when assigned, unmutes the mic while held and re-mutes on
    // release (hold-to-talk).
    static func install() {
        KeyboardShortcuts.onKeyDown(for: .toggleMute) {
            AudioController.shared.toggle()
        }

        KeyboardShortcuts.onKeyDown(for: .pushToTalk) {
            guard !isTalking else { return }
            isTalking = true
            AudioController.shared.setMutedState(false)
        }
        KeyboardShortcuts.onKeyUp(for: .pushToTalk) {
            isTalking = false
            AudioController.shared.setMutedState(true)
        }
    }
}
