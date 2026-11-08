import Foundation
import LedgeCore

/// Everything the user can change, stored as one JSON blob in UserDefaults.
struct Settings: Codable, Equatable {
    var version = Settings.currentVersion
    var enabled = true
    var sliderLayout: SliderLayout = .sides
    var leftAction: EdgeAction = .brightness
    var rightAction: EdgeAction = .volume
    var activeArea: ActiveArea = .full
    var requireModifier = false
    var ignoreWhileTyping = true
    var controlCenterSwipe = false
    var tapActions: [TapZone: TapAction] = [.topRight: .mute]
    var mediaStrip = true
    var reverseMediaSwipe = false
    var haptics: HapticStrength = .medium
    var sensitivity = 1.5
    var edgeWidth = 0.07
    var stepSize: StepSize = .smooth
    var freezePointer = true
    var blockScrolling = true
    var fineControl = true
    var hudStyle: HUDStyle = .system
    var appearance: AppearanceMode = .auto
    var hasSeenSetup = false

    static let currentVersion = 2

    init() {}

    // Decode field by field so settings saved by an older build keep working.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decode(T.self, forKey: key)) ?? fallback
        }
        version = value(.version, 1)
        enabled = value(.enabled, d.enabled)
        sliderLayout = value(.sliderLayout, d.sliderLayout)
        leftAction = value(.leftAction, d.leftAction)
        rightAction = value(.rightAction, d.rightAction)
        activeArea = value(.activeArea, d.activeArea)
        requireModifier = value(.requireModifier, d.requireModifier)
        ignoreWhileTyping = value(.ignoreWhileTyping, d.ignoreWhileTyping)
        controlCenterSwipe = value(.controlCenterSwipe, d.controlCenterSwipe)
        tapActions = value(.tapActions, d.tapActions)
        mediaStrip = value(.mediaStrip, d.mediaStrip)
        reverseMediaSwipe = value(.reverseMediaSwipe, d.reverseMediaSwipe)
        haptics = value(.haptics, d.haptics)
        sensitivity = value(.sensitivity, d.sensitivity)
        edgeWidth = value(.edgeWidth, d.edgeWidth)
        stepSize = value(.stepSize, d.stepSize)
        freezePointer = value(.freezePointer, d.freezePointer)
        blockScrolling = value(.blockScrolling, d.blockScrolling)
        fineControl = value(.fineControl, d.fineControl)
        hudStyle = value(.hudStyle, d.hudStyle)
        appearance = value(.appearance, d.appearance)
        hasSeenSetup = value(.hasSeenSetup, d.hasSeenSetup)

        if version < 2 {
            // 1.0 used a narrower 5% edge by default, which was easy to miss.
            if edgeWidth == 0.05 { edgeWidth = d.edgeWidth }
            version = Settings.currentVersion
        }
    }

    func action(for edge: Side) -> EdgeAction {
        edge == .left ? leftAction : rightAction
    }

    var gestureConfig: GestureConfig {
        var config = GestureConfig()
        config.layout = sliderLayout
        config.edgeWidth = edgeWidth
        config.activeArea = activeArea
        config.leftEdge = leftAction != .off
        config.rightEdge = rightAction != .off
        config.mediaStrip = mediaStrip
        config.tapZones = Set(tapActions.filter { $0.value != .none }.keys)
        config.ignoreWhileTyping = ignoreWhileTyping
        config.pullDown = controlCenterSwipe
        return config
    }

    func tapAction(for zone: TapZone) -> TapAction {
        tapActions[zone] ?? .none
    }
}

final class Preferences: ObservableObject {
    static let shared = Preferences()

    private static let key = "settings.v1"

    @Published var settings: Settings {
        didSet {
            guard settings != oldValue, let data = try? JSONEncoder().encode(settings) else { return }
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = saved
        } else {
            settings = Settings()
        }
    }
}
