import AppKit
import AudioToolbox
import CoreAudio
import LedgePrivate

/// Output volume and mute of the current default output device.
enum Volume {
    private static func defaultOutputDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != 0 ? device : nil
    }

    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    /// 0...1, or nil when the device has no software volume (e.g. HDMI).
    static func get() -> Double? {
        guard let device = defaultOutputDevice() else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioHardwareServiceGetPropertyData(device, &volumeAddress, 0, nil, &size, &value)
        return status == noErr ? Double(value) : nil
    }

    @discardableResult
    static func set(_ value: Double) -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        var volume = Float32(min(1, max(0, value)))
        let status = AudioHardwareServiceSetPropertyData(device, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
        return status == noErr
    }

    static var isMuted: Bool {
        guard let device = defaultOutputDevice() else { return false }
        var muted = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &size, &muted)
        return status == noErr && muted != 0
    }

    static func setMuted(_ muted: Bool) {
        guard let device = defaultOutputDevice() else { return }
        var value = UInt32(muted ? 1 : 0)
        AudioObjectSetPropertyData(device, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }
}

/// Brightness of the built-in display.
enum Brightness {
    static var builtInDisplay: CGDirectDisplayID? {
        var count = UInt32(0)
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
        return displays.first { CGDisplayIsBuiltin($0) != 0 }
    }

    static func get() -> Double? {
        guard let display = builtInDisplay else { return nil }
        var value = Float(0)
        return DisplayServicesGetBrightness(display, &value) == 0 ? Double(value) : nil
    }

    @discardableResult
    static func set(_ value: Double) -> Bool {
        guard let display = builtInDisplay else { return false }
        return DisplayServicesSetBrightness(display, Float(min(1, max(0, value)))) == 0
    }
}

/// Backlight of the built-in keyboard (M-series MacBooks have no keys for it).
enum KeyboardLight {
    static var isAvailable: Bool { LGKeyboardBacklightAvailable() }

    static func get() -> Double? {
        var value = Float(0)
        return LGGetKeyboardBacklight(&value) ? Double(value) : nil
    }

    @discardableResult
    static func set(_ value: Double) -> Bool {
        LGSetKeyboardBacklight(Float(min(1, max(0, value))))
    }
}

/// Synthesised media keys, the same events the F7–F9 keys send.
enum MediaKey: Int32 {
    case playPause = 16 // NX_KEYTYPE_PLAY
    case next = 17      // NX_KEYTYPE_NEXT
    case previous = 18  // NX_KEYTYPE_PREVIOUS

    func post() {
        for isDown in [true, false] {
            let state = isDown ? 0xA : 0xB
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: Int((rawValue << 16) | Int32(state << 8)),
                data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}

enum SystemActions {
    static func openMissionControl() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
    }

    /// Same as pressing ⌃⌘Q.
    static func lockScreen() {
        let source = CGEventSource(stateID: .hidSystemState)
        let qKey: CGKeyCode = 12
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: qKey, keyDown: isDown)
            event?.flags = [.maskCommand, .maskControl]
            event?.post(tap: .cghidEventTap)
        }
    }
}
