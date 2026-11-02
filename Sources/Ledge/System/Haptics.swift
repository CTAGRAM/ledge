import AppKit
import LedgeCore
import LedgePrivate

/// Taps the Force Touch trackpad under the finger.
///
/// Uses the trackpad's own actuator (the IDs HapticKey found in MultitouchSupport),
/// which works from a background app, and falls back to NSHapticFeedbackManager.
final class Haptics {
    var strength: HapticStrength = .medium

    private var actuators: [UInt64: MTActuator] = [:]
    private var lastTick = 0.0
    private let minimumInterval = 0.018

    /// A light tick for every step of a slide.
    func tick(on deviceID: UInt64?) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastTick >= minimumInterval else { return }
        lastTick = now
        actuate(id: actuationID(for: strength), on: deviceID)
    }

    /// A firmer bump for mute and other one-off actions, so you can feel it without looking.
    func bump(on deviceID: UInt64?) {
        guard strength != .off else { return }
        actuate(id: 6, on: deviceID)
    }

    func closeAll() {
        for actuator in actuators.values { MTActuatorClose(actuator) }
        actuators.removeAll()
    }

    private func actuationID(for strength: HapticStrength) -> Int32 {
        switch strength {
        case .off: return 0
        case .light: return 3
        case .medium: return 4
        case .strong: return 6
        }
    }

    private func actuate(id: Int32, on deviceID: UInt64?) {
        guard id != 0 else { return }
        if let deviceID, let actuator = actuator(for: deviceID) {
            if MTActuatorActuate(actuator, id, 0, 0, 2) == kIOReturnSuccess { return }
            // The trackpad may have gone to sleep; reopen once.
            MTActuatorClose(actuator)
            actuators[deviceID] = nil
            if let fresh = self.actuator(for: deviceID), MTActuatorActuate(fresh, id, 0, 0, 2) == kIOReturnSuccess { return }
        }
        let pattern: NSHapticFeedbackManager.FeedbackPattern = id >= 6 ? .levelChange : .alignment
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    private func actuator(for deviceID: UInt64) -> MTActuator? {
        if let existing = actuators[deviceID] { return existing }
        guard let created = MTActuatorCreateFromDeviceID(deviceID)?.takeRetainedValue(),
              MTActuatorOpen(created) == kIOReturnSuccess else { return nil }
        actuators[deviceID] = created
        return created
    }
}
