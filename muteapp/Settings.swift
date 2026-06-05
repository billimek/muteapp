import Foundation

enum TargetMode: String {
    case followDefault
    case specificDevice
}

struct Settings {
    private static let modeKey = "targetMode"
    private static let uidKey = "targetDeviceUID"
    private static let restoreLevelsKey = "restoreLevelsByUID"
    private static let hudKey = "hudEnabled"
    private static let soundKey = "soundEnabled"

    static var hudEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: hudKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: hudKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: hudKey) }
    }

    // Whether a sound effect plays when the microphone is muted or unmuted. Defaults to `false`.
    static var soundEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: soundKey) }
        set { UserDefaults.standard.set(newValue, forKey: soundKey) }
    }

    static var targetMode: TargetMode {
        get {
            UserDefaults.standard.string(forKey: modeKey)
                .flatMap(TargetMode.init(rawValue:)) ?? .followDefault
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: modeKey) }
    }

    static var targetDeviceUID: String? {
        get { UserDefaults.standard.string(forKey: uidKey) }
        set { UserDefaults.standard.set(newValue, forKey: uidKey) }
    }

    // Cache prior input volume per-device-UID for the volume-fallback path.
    static func restoreLevel(for uid: String) -> Float? {
        let dict = UserDefaults.standard.dictionary(forKey: restoreLevelsKey) ?? [:]
        return dict[uid] as? Float
    }

    static func setRestoreLevel(_ level: Float?, for uid: String) {
        var dict = UserDefaults.standard.dictionary(forKey: restoreLevelsKey) ?? [:]
        if let level { dict[uid] = level } else { dict.removeValue(forKey: uid) }
        UserDefaults.standard.set(dict, forKey: restoreLevelsKey)
    }
}
