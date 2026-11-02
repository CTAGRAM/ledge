import Foundation

/// A single finger on a multitouch surface, in normalized coordinates.
public struct Touch: Equatable {
    public enum Phase: Equatable {
        /// Firm contact.
        case touching
        /// The sensor sees the finger but has lost firm contact; often it comes straight back.
        case hovering
        /// The finger has left the surface.
        case lifted
    }

    public var id: Int32
    /// 0 at the left edge, 1 at the right edge.
    public var x: Double
    /// 0 at the bottom edge, 1 at the top edge.
    public var y: Double
    public var phase: Phase
    /// Long axis of the contact ellipse as the sensor reports it; palms are far larger than fingertips.
    public var majorAxis: Double
    /// Contact strength (capacitance), larger for a palm or a flat thumb.
    public var size: Double

    public init(id: Int32, x: Double, y: Double, phase: Phase = .touching, majorAxis: Double = 0, size: Double = 0) {
        self.id = id
        self.x = x
        self.y = y
        self.phase = phase
        self.majorAxis = majorAxis
        self.size = size
    }
}

/// Physical size of a touch surface, used so gestures feel the same on every trackpad.
public struct SurfaceSize: Equatable {
    public var widthMM: Double
    public var heightMM: Double

    public init(widthMM: Double, heightMM: Double) {
        self.widthMM = widthMM
        self.heightMM = heightMM
    }

    /// Close to a 14" MacBook Pro trackpad; used when the device does not report its size.
    public static let fallback = SurfaceSize(widthMM: 150, heightMM: 95)
}

public enum Side: String, Codable, CaseIterable { case left, right }

/// A section of the trackpad that reacts to a double-tap.
public enum TapZone: String, Codable, CaseIterable, Identifiable, CodingKeyRepresentable {
    case topLeft, topCenter, topRight, bottomLeft, bottomCenter, bottomRight

    public var id: String { rawValue }
    public var isTop: Bool { self == .topLeft || self == .topCenter || self == .topRight }

    public var title: String {
        switch self {
        case .topLeft: return "Top-Left Corner"
        case .topCenter: return "Top Middle"
        case .topRight: return "Top-Right Corner"
        case .bottomLeft: return "Bottom-Left Corner"
        case .bottomCenter: return "Bottom Middle"
        case .bottomRight: return "Bottom-Right Corner"
        }
    }
}

/// Where along a side edge a slide is allowed to start.
public enum ActiveArea: String, Codable, CaseIterable, Identifiable {
    case full, bottomThreeQuarters, bottomHalf, bottomQuarter

    public var id: String { rawValue }

    public var fraction: Double {
        switch self {
        case .full: return 1
        case .bottomThreeQuarters: return 0.75
        case .bottomHalf: return 0.5
        case .bottomQuarter: return 0.25
        }
    }

    public var title: String {
        switch self {
        case .full: return "Whole edge"
        case .bottomThreeQuarters: return "Bottom ¾"
        case .bottomHalf: return "Bottom half"
        case .bottomQuarter: return "Bottom quarter"
        }
    }
}

/// What a side edge controls.
public enum EdgeAction: String, Codable, CaseIterable, Identifiable {
    case brightness, volume, keyboardBacklight, off

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .brightness: return "Brightness"
        case .volume: return "Volume"
        case .keyboardBacklight: return "Keyboard Light"
        case .off: return "Nothing"
        }
    }
}

/// A key combination to press, e.g. ⌘⇧4.
public struct KeyCombo: Codable, Hashable {
    public var keyCode: UInt16
    /// CGEventFlags raw value (command, option, control, shift, fn).
    public var modifiers: UInt64
    /// What to show in the UI, e.g. "⌘⇧4".
    public var display: String

    public init(keyCode: UInt16, modifiers: UInt64, display: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.display = display
    }
}

/// What a double-tap on a section does.
public enum TapAction: Codable, Hashable {
    case none
    case mute, playPause, nextTrack, previousTrack
    case missionControl, showDesktop, lockScreen, screenshot
    case openApp(path: String)
    case runShortcut(name: String)
    case openURL(String)
    case keyboardShortcut(KeyCombo)
    case shellCommand(String)
    case timer(minutes: Int)

    /// The type of action without its settings, for pickers.
    public enum Kind: String, CaseIterable, Identifiable {
        case none, mute, playPause, nextTrack, previousTrack
        case missionControl, showDesktop, lockScreen, screenshot
        case openApp, runShortcut, openURL, keyboardShortcut, shellCommand, timer

        public var id: String { rawValue }
    }

    public var kind: Kind {
        switch self {
        case .none: return .none
        case .mute: return .mute
        case .playPause: return .playPause
        case .nextTrack: return .nextTrack
        case .previousTrack: return .previousTrack
        case .missionControl: return .missionControl
        case .showDesktop: return .showDesktop
        case .lockScreen: return .lockScreen
        case .screenshot: return .screenshot
        case .openApp: return .openApp
        case .runShortcut: return .runShortcut
        case .openURL: return .openURL
        case .keyboardShortcut: return .keyboardShortcut
        case .shellCommand: return .shellCommand
        case .timer: return .timer
        }
    }

    /// A fresh action of the given kind with empty settings.
    public init(kind: Kind) {
        switch kind {
        case .none: self = .none
        case .mute: self = .mute
        case .playPause: self = .playPause
        case .nextTrack: self = .nextTrack
        case .previousTrack: self = .previousTrack
        case .missionControl: self = .missionControl
        case .showDesktop: self = .showDesktop
        case .lockScreen: self = .lockScreen
        case .screenshot: self = .screenshot
        case .openApp: self = .openApp(path: "")
        case .runShortcut: self = .runShortcut(name: "")
        case .openURL: self = .openURL("")
        case .keyboardShortcut: self = .keyboardShortcut(KeyCombo(keyCode: 0, modifiers: 0, display: ""))
        case .shellCommand: self = .shellCommand("")
        case .timer: self = .timer(minutes: 5)
        }
    }
}

/// How finely a slide changes the level.
public enum StepSize: String, Codable, CaseIterable, Identifiable {
    /// 1% steps, with a haptic detent every sixteenth like the keyboard.
    case smooth
    /// 64 steps, like ⇧⌥ with the keyboard keys.
    case quarter
    /// 16 steps, exactly like the keyboard keys.
    case standard

    public var id: String { rawValue }

    public var steps: Int {
        switch self {
        case .smooth: return 100
        case .quarter: return 64
        case .standard: return 16
        }
    }

    public var title: String {
        switch self {
        case .smooth: return "Smooth"
        case .quarter: return "Quarter Steps"
        case .standard: return "Keyboard Steps"
        }
    }
}

public enum HapticStrength: String, Codable, CaseIterable, Identifiable {
    case off, light, medium, strong

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public enum HUDStyle: String, Codable, CaseIterable, Identifiable {
    /// The same HUD the keyboard brightness/volume keys show.
    case system
    /// A slim level bar on the side of the screen that matches the trackpad edge.
    case edge
    case off

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: return "System"
        case .edge: return "Edge Bar"
        case .off: return "None"
        }
    }
}

public enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case auto, light, dark

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}
