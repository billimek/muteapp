import SwiftUI
import ServiceManagement
import KeyboardShortcuts

@MainActor
final class PopoverModel: ObservableObject {
    @Published var muted: Bool = false
    @Published var devices: [InputDevice] = []
    @Published var targetMode: TargetMode = .followDefault
    @Published var targetUID: String? = nil
    @Published var hudEnabled: Bool = Settings.hudEnabled
    @Published var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled)

    private var observers: [NSObjectProtocol] = []

    init() {
        refreshFromSettings()
        refreshDevices()
        muted = AudioController.shared.currentMuted()

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .muteStateChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.muted = AudioController.shared.currentMuted() }
        })
        observers.append(nc.addObserver(forName: .inputDevicesChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDevices()
                self?.refreshFromSettings()
            }
        })
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func refreshDevices() {
        devices = AudioController.shared.listInputDevices()
    }

    func refreshFromSettings() {
        targetMode = Settings.targetMode
        targetUID = Settings.targetDeviceUID
        hudEnabled = Settings.hudEnabled
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    func toggleMute() {
        AudioController.shared.toggle()
    }

    func selectFollowDefault() {
        Settings.targetMode = .followDefault
        Settings.targetDeviceUID = nil
        AudioController.shared.installMuteListenerForCurrentTarget()
        refreshFromSettings()
        muted = AudioController.shared.currentMuted()
    }

    func selectDevice(_ uid: String) {
        Settings.targetMode = .specificDevice
        Settings.targetDeviceUID = uid
        AudioController.shared.installMuteListenerForCurrentTarget()
        refreshFromSettings()
        muted = AudioController.shared.currentMuted()
    }

    func setHUDEnabled(_ value: Bool) {
        Settings.hudEnabled = value
        hudEnabled = value
    }

    func setLaunchAtLogin(_ value: Bool) {
        let svc = SMAppService.mainApp
        do {
            if value { try svc.register() } else { try svc.unregister() }
        } catch {
            NSLog("muteapp: launch-at-login toggle failed: \(error)")
        }
        launchAtLogin = (svc.status == .enabled)
    }
}

struct PopoverView: View {
    @StateObject var model = PopoverModel()

    var body: some View {
        VStack(spacing: 14) {
            MicGlyph(muted: model.muted)
                .padding(.top, 16)

            VStack(spacing: 2) {
                Text(model.muted ? "Muted" : "Live")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(model.muted ? Theme.muted : Theme.live)
                Text(model.muted ? "Microphone is muted" : "Microphone is active")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }

            MuteButton(muted: model.muted) { model.toggleMute() }

            SectionHeader("INPUT DEVICE")
            DeviceList(model: model)

            SectionHeader("SETTINGS")
            SettingsRows(model: model)

            Footer()
                .padding(.top, 4)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.gradient)
    }
}

// MARK: - Subviews

private struct MicGlyph: View {
    let muted: Bool
    var body: some View {
        let tint = muted ? Theme.muted : Theme.live
        ZStack {
            Circle()
                .fill(tint.opacity(0.18))
                .frame(width: 96, height: 96)
                .blur(radius: 12)
            Circle()
                .stroke(tint.opacity(0.85), lineWidth: 3)
                .frame(width: 76, height: 76)
            Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(tint)
        }
        .animation(.easeInOut(duration: 0.18), value: muted)
    }
}

private struct MuteButton: View {
    let muted: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: muted ? "mic.fill" : "mic.slash.fill")
                Text(muted ? "Unmute" : "Mute")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if let s = KeyboardShortcuts.getShortcut(for: .toggleMute) {
                    Text(s.description)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .foregroundStyle(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
    }
}

private struct DeviceList: View {
    @ObservedObject var model: PopoverModel
    var body: some View {
        VStack(spacing: 0) {
            DeviceRow(
                icon: "dot.radiowaves.left.and.right",
                name: "Follow current default",
                selected: model.targetMode == .followDefault
            ) { model.selectFollowDefault() }

            ForEach(model.devices, id: \.uid) { dev in
                Divider().background(Theme.stroke)
                DeviceRow(
                    icon: deviceIcon(name: dev.name),
                    name: dev.name,
                    selected: model.targetMode == .specificDevice && model.targetUID == dev.uid
                ) { model.selectDevice(dev.uid) }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
    }

    private func deviceIcon(name: String) -> String {
        let lc = name.lowercased()
        if lc.contains("airpod") || lc.contains("headphone") || lc.contains("headset") || lc.contains("beats") {
            return "headphones"
        }
        if lc.contains("macbook") || lc.contains("imac") || lc.contains("built") {
            return "laptopcomputer"
        }
        return "mic"
    }
}

private struct DeviceRow: View {
    let icon: String
    let name: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 18)
                    .foregroundStyle(Theme.textSecondary)
                Text(name)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.live)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsRows: View {
    @ObservedObject var model: PopoverModel
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "command")
                    .frame(width: 18)
                    .foregroundStyle(Theme.textSecondary)
                Text("Hotkey")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                KeyboardShortcuts.Recorder(for: .toggleMute)
                    .controlSize(.small)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 12)

            Divider().background(Theme.stroke)

            HStack {
                Image(systemName: "mic.badge.plus")
                    .frame(width: 18)
                    .foregroundStyle(Theme.textSecondary)
                Text("Push to talk")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                KeyboardShortcuts.Recorder(for: .pushToTalk)
                    .controlSize(.small)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 12)

            Divider().background(Theme.stroke)

            ToggleRow(
                icon: "rectangle.center.inset.filled",
                title: "Show on-screen HUD",
                isOn: Binding(
                    get: { model.hudEnabled },
                    set: { model.setHUDEnabled($0) }
                )
            )

            Divider().background(Theme.stroke)

            ToggleRow(
                icon: "power",
                title: "Launch at Login",
                isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                )
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
    }
}

private struct ToggleRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(Theme.textSecondary)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Theme.live)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
    }
}

private struct Footer: View {
    var body: some View {
        HStack {
            Button {
                NSWorkspace.shared.open(Theme.releasesURL)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.circle")
                    Text("Check for Updates")
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(versionLabel)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary.opacity(0.7))

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                HStack(spacing: 4) {
                    Text("Quit")
                    Text("⌘Q").foregroundStyle(Theme.textSecondary.opacity(0.7))
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    private var versionLabel: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "v\(v)"
    }
}
