import Foundation
import CoreAudio

extension Notification.Name {
    static let muteStateChanged = Notification.Name("muteStateChanged")
    static let inputDevicesChanged = Notification.Name("inputDevicesChanged")
}

struct InputDevice: Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

final class AudioController {
    static let shared = AudioController()

    private var defaultInputListenerInstalled = false
    private var muteListenerDeviceID: AudioDeviceID?

    private init() {
        installDefaultInputListener()
        installMuteListenerForCurrentTarget()
    }

    // MARK: Public

    func toggle() {
        guard let id = resolveTargetDeviceID() else {
            NSLog("muteapp: no target device resolvable")
            return
        }
        let nowMuted = isMuted(id) ?? false
        setMuted(id, !nowMuted)
        NotificationCenter.default.post(name: .muteStateChanged, object: nil)
    }

    func currentMuted() -> Bool {
        guard let id = resolveTargetDeviceID() else { return false }
        return isMuted(id) ?? false
    }

    // Forces the target device to the given mute state and notifies observers.
    //
    // Unlike ``toggle()`` this sets an absolute state, which is what the
    // push-to-talk handlers need (unmute on key down, mute on key up).
    // - Parameter muted: `true` to mute the target device, `false` to unmute.
    func setMutedState(_ muted: Bool) {
        guard let id = resolveTargetDeviceID() else {
            NSLog("muteapp: no target device resolvable")
            return
        }
        setMuted(id, muted)
        NotificationCenter.default.post(name: .muteStateChanged, object: nil)
    }

    func listInputDevices() -> [InputDevice] {
        var size: UInt32 = 0
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size
        ) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids
        ) == noErr else { return [] }

        return ids.compactMap { id -> InputDevice? in
            guard hasInputStreams(id) else { return nil }
            guard let uid = stringProperty(id, kAudioDevicePropertyDeviceUID) else { return nil }
            let name = stringProperty(id, kAudioObjectPropertyName) ?? uid
            return InputDevice(id: id, uid: uid, name: name)
        }
    }

    func resolveTargetDeviceID() -> AudioDeviceID? {
        switch Settings.targetMode {
        case .followDefault:
            return defaultInputDeviceID()
        case .specificDevice:
            guard let wantedUID = Settings.targetDeviceUID else {
                return defaultInputDeviceID()
            }
            return listInputDevices().first(where: { $0.uid == wantedUID })?.id
        }
    }

    // MARK: Mute primitive

    func isMuted(_ id: AudioDeviceID) -> Bool? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(id, &addr) {
            var muted: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &muted) == noErr {
                return muted != 0
            }
        }
        // Fallback: treat zero input volume as muted.
        if let vol = inputVolume(id) {
            return vol <= 0.0001
        }
        return nil
    }

    func setMuted(_ id: AudioDeviceID, _ muted: Bool) {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var settable: DarwinBoolean = false
        let hasMute = AudioObjectHasProperty(id, &addr)
        if hasMute {
            _ = AudioObjectIsPropertySettable(id, &addr, &settable)
        }
        if hasMute && settable.boolValue {
            var value: UInt32 = muted ? 1 : 0
            let status = AudioObjectSetPropertyData(
                id, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value
            )
            if status == noErr { return }
            NSLog("muteapp: kAudioDevicePropertyMute set failed (\(status)); falling back to volume")
        }
        // Volume-scalar fallback.
        guard let uid = stringProperty(id, kAudioDevicePropertyDeviceUID) else { return }
        if muted {
            if let cur = inputVolume(id), cur > 0 {
                Settings.setRestoreLevel(cur, for: uid)
            }
            setInputVolume(id, 0)
        } else {
            let restore = Settings.restoreLevel(for: uid) ?? 1.0
            setInputVolume(id, restore)
        }
    }

    // MARK: Helpers

    private func defaultInputDeviceID() -> AudioDeviceID? {
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id
        ) == noErr else { return nil }
        return id == 0 ? nil : id
    }

    private func hasInputStreams(_ id: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr else { return false }
        return size > 0
    }

    private func stringProperty(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cf: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &cf) { ptr -> OSStatus in
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, ptr)
        }
        return status == noErr ? (cf as String) : nil
    }

    private func inputVolume(_ id: AudioDeviceID) -> Float? {
        // Try master element first, then channel 1.
        for element in [kAudioObjectPropertyElementMain, AudioObjectPropertyElement(1)] {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: element
            )
            if AudioObjectHasProperty(id, &addr) {
                var value: Float32 = 0
                var size = UInt32(MemoryLayout<Float32>.size)
                if AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr {
                    return value
                }
            }
        }
        return nil
    }

    private func setInputVolume(_ id: AudioDeviceID, _ value: Float) {
        for element in [kAudioObjectPropertyElementMain, AudioObjectPropertyElement(1), AudioObjectPropertyElement(2)] {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: element
            )
            var settable: DarwinBoolean = false
            if AudioObjectHasProperty(id, &addr),
               AudioObjectIsPropertySettable(id, &addr, &settable) == noErr,
               settable.boolValue {
                var v = value
                _ = AudioObjectSetPropertyData(
                    id, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v
                )
            }
        }
    }

    // MARK: Listeners

    private let propertyListener: AudioObjectPropertyListenerBlock = { _, _ in
        NotificationCenter.default.post(name: .muteStateChanged, object: nil)
    }

    private let defaultInputListener: AudioObjectPropertyListenerBlock = { _, _ in
        NotificationCenter.default.post(name: .inputDevicesChanged, object: nil)
        AudioController.shared.installMuteListenerForCurrentTarget()
        NotificationCenter.default.post(name: .muteStateChanged, object: nil)
    }

    private func installDefaultInputListener() {
        guard !defaultInputListenerInstalled else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &addr, .main, defaultInputListener
        )
        defaultInputListenerInstalled = (status == noErr)
    }

    func installMuteListenerForCurrentTarget() {
        if let prev = muteListenerDeviceID {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(prev, &addr, .main, propertyListener)
            muteListenerDeviceID = nil
        }
        guard let id = resolveTargetDeviceID() else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(id, &addr) {
            let status = AudioObjectAddPropertyListenerBlock(id, &addr, .main, propertyListener)
            if status == noErr { muteListenerDeviceID = id }
        }
    }
}
