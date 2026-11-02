import AppKit
import LedgeCore

/// Live state shown in the menu: levels, permission, devices and fingers.
final class AppModel: ObservableObject {
    static let shared = AppModel()

    enum Status: Equatable {
        case ready, paused, needsAccess, noTrackpad

        var title: String {
            switch self {
            case .ready: return "Ready"
            case .paused: return "Paused"
            case .needsAccess: return "Needs Access"
            case .noTrackpad: return "No Trackpad"
            }
        }
    }

    @Published var brightness: Double?
    @Published var volume: Double?
    @Published var muted = false
    @Published var keyboardLight: Double?
    @Published var accessibilityGranted = false
    @Published var devices: [TrackpadDevice] = []
    /// Fingers on the trackpad, only updated while the menu is open.
    @Published var touches: [Touch] = []
    @Published var activeEdge: Side?
    var menuIsOpen = false

    func status(enabled: Bool) -> Status {
        if !enabled { return .paused }
        if !accessibilityGranted { return .needsAccess }
        if devices.isEmpty { return .noTrackpad }
        return .ready
    }

    var primarySurface: SurfaceSize {
        (devices.first(where: \.isBuiltIn) ?? devices.first)?.surface ?? .fallback
    }

    func value(for action: EdgeAction) -> Double? {
        switch action {
        case .brightness: return brightness
        case .volume: return muted ? 0 : volume
        case .keyboardBacklight: return keyboardLight
        case .off: return nil
        }
    }

    /// Re-reads every level from the system.
    func refreshLevels() {
        let newBrightness = Brightness.get()
        let newVolume = Volume.get()
        let newMuted = Volume.isMuted
        let newKeyboard = KeyboardLight.get()
        if newBrightness != brightness { brightness = newBrightness }
        if newVolume != volume { volume = newVolume }
        if newMuted != muted { muted = newMuted }
        if newKeyboard != keyboardLight { keyboardLight = newKeyboard }
    }
}
