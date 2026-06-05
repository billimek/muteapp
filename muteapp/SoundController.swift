import AppKit

// Plays short sound effects when the microphone's mute state changes.
//
// Sounds are preloaded once from the app bundle and reused for the lifetime of
// the process. Playback is gated on `Settings.soundEnabled`, so the controller
// is a no-op when the feature is turned off.
@MainActor
final class SoundController {
    static let shared = SoundController()

    private let muteSound: NSSound?
    private let unmuteSound: NSSound?

    private init() {
        muteSound = SoundController.loadSound(named: "mute")
        unmuteSound = SoundController.loadSound(named: "unmute")
    }

    // Plays the sound matching the new mute state, if sound effects are enabled.
    //
    // - Parameter muted: `true` to play the mute sound, `false` for unmute.
    func play(muted: Bool) {
        guard Settings.soundEnabled else { return }
        let sound = muted ? muteSound : unmuteSound
        guard let sound else { return }
        // Restart from the beginning if it's still playing from a rapid toggle.
        if sound.isPlaying { sound.stop() }
        sound.play()
    }

    // Loads a `.wav` resource from the app bundle by base name.
    //
    // - Parameter name: The file's base name, without the `.wav` extension.
    // - Returns: An `NSSound` instance, or `nil` if the resource is missing.
    private static func loadSound(named name: String) -> NSSound? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
            NSLog("muteapp: missing sound resource \(name).wav")
            return nil
        }
        return NSSound(contentsOf: url, byReference: true)
    }
}
