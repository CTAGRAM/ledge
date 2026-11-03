import AppKit
import Combine
import LedgeCore
import os

private let log = Logger(subsystem: "app.ledge.Ledge", category: "gestures")

/// Connects trackpad frames → gesture recognizers → volume, brightness, media and HUD.
final class EdgeController {
    private let prefs: Preferences
    private let model: AppModel
    private let monitor = TrackpadMonitor.shared
    private let pointer = PointerControl()
    private let haptics = Haptics()
    private let hud = HUDPresenter()

    private var recognizers: [UInt: EdgeGestureRecognizer] = [:]
    private struct Slide {
        var edge: Side
        var action: EdgeAction
        var accumulator: StepAccumulator
        var deviceID: UInt64
        var muted: Bool
        /// Which sixteenth the level was in at the last haptic tick.
        var detent: Int
    }

    private var slide: Slide?
    private var pointerAnchor: CGPoint?
    private var lastTouchPublish = 0.0
    private var tickWork: DispatchWorkItem?
    private var accessTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// Finger travel (mm) that sweeps the whole 0–100% range at 1× sensitivity.
    private let fullRangeTravelMM = 80.0

    init(prefs: Preferences = .shared, model: AppModel = .shared) {
        self.prefs = prefs
        self.model = model
    }

    func start() {
        monitor.onFrame = { [weak self] device, touches in self?.handle(touches, from: device) }
        monitor.onDevicesChanged = { [weak self] devices in
            guard let self else { return }
            let keys = Set(devices.map(\.key))
            recognizers = recognizers.filter { keys.contains($0.key) }
            endSlide()
            model.devices = devices
        }
        monitor.start()
        monitor.watchForChanges()

        pointer.onMouseDown = { [weak self] in
            let now = ProcessInfo.processInfo.systemUptime
            self?.recognizers.values.forEach { $0.noteMouseDown(at: now) }
        }
        pointer.onKeyDown = { [weak self] in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            recognizers.values.forEach { $0.noteKeyDown(at: now) }
            updatePointerGuards()
        }

        prefs.$settings
            .sink { [weak self] settings in self?.apply(settings) }
            .store(in: &cancellables)

        model.refreshLevels()
        checkAccessibility()
    }

    func stop() {
        endSlide()
        pointer.stop()
        monitor.stop()
        haptics.closeAll()
    }

    // MARK: Accessibility

    /// Starts the event tap once Accessibility is granted, polling until then.
    func checkAccessibility(prompt: Bool = false) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        model.accessibilityGranted = trusted
        if trusted {
            accessTimer?.invalidate()
            accessTimer = nil
            pointer.start()
        } else if accessTimer == nil {
            accessTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.checkAccessibility()
            }
        }
    }

    // MARK: Settings

    private func apply(_ settings: Settings) {
        let config = settings.gestureConfig
        recognizers.values.forEach { $0.config = config }
        haptics.strength = settings.haptics
        hud.style = settings.hudStyle
        pointer.hidesPointer = settings.freezePointer
        if !settings.enabled || (slide.map { settings.action(for: $0.edge) != $0.action } ?? false) {
            resetRecognizers()
        }
        NSApp?.appearance = switch settings.appearance {
        case .auto: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    private func recognizer(for device: TrackpadDevice) -> EdgeGestureRecognizer {
        if let existing = recognizers[device.key] { return existing }
        let recognizer = EdgeGestureRecognizer(config: prefs.settings.gestureConfig, surface: device.surface)
        recognizer.gesturesAllowed = { [weak self] in
            guard let self, prefs.settings.requireModifier else { return true }
            let flags = CGEventSource.flagsState(.combinedSessionState)
            return flags.contains(.maskSecondaryFn) || flags.contains(.maskAlternate)
        }
        recognizers[device.key] = recognizer
        return recognizer
    }

    // MARK: Frames

    private func handle(_ touches: [Touch], from device: TrackpadDevice) {
        if model.menuIsOpen, device.isBuiltIn || model.devices.count == 1 {
            publishTouches(touches.filter { $0.phase == .touching })
        }
        guard prefs.settings.enabled else { return }

        let recognizer = recognizer(for: device)
        let wasTracking = recognizer.isTracking
        let now = ProcessInfo.processInfo.systemUptime
        let events = recognizer.process(touches, at: now)
        if !wasTracking, recognizer.isTracking {
            // Remember where the pointer was when the finger landed, to put it back after the slide.
            pointerAnchor = PointerControl.location
        }
        events.forEach { perform($0, device: device) }
        scheduleTickIfNeeded(recognizer, device: device)
        updatePointerGuards()
    }

    /// Tells the event tap whether to hold back scrolling and section-tap clicks.
    private func updatePointerGuards() {
        let all = recognizers.values
        pointer.update(blockScrolling: prefs.settings.blockScrolling && all.contains(where: \.blocksScrolling),
                       sliding: all.contains(where: \.isSliding),
                       clickGuardDown: all.contains(where: \.clickGuardDown),
                       clickGuardUntil: all.map(\.clickGuardDeadline).max() ?? 0)
    }

    /// The trackpad reports ~120 frames a second; the map only needs ~30 to look live.
    private func publishTouches(_ touches: [Touch]) {
        let now = ProcessInfo.processInfo.systemUptime
        let countChanged = touches.count != model.touches.count
        guard countChanged || now - lastTouchPublish >= 1.0 / 30 else { return }
        lastTouchPublish = now
        if touches != model.touches { model.touches = touches }
    }

    private func scheduleTickIfNeeded(_ recognizer: EdgeGestureRecognizer, device: TrackpadDevice) {
        tickWork?.cancel()
        guard recognizer.needsTick else { return }
        let work = DispatchWorkItem { [weak self, weak recognizer] in
            guard let self, let recognizer else { return }
            recognizer.tick(at: ProcessInfo.processInfo.systemUptime).forEach { self.perform($0, device: device) }
            self.scheduleTickIfNeeded(recognizer, device: device)
            self.updatePointerGuards()
        }
        tickWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func resetRecognizers() {
        recognizers.values.forEach { _ = $0.reset() }
        endSlide()
        updatePointerGuards()
    }

    // MARK: Gestures → actions

    private func perform(_ event: GestureEvent, device: TrackpadDevice) {
        switch event {
        case .slideBegan(let edge):
            log.notice("slide began on \(edge.rawValue, privacy: .public) edge")
            beginSlide(on: edge, device: device)
        case .slideMoved(let edge, let deltaMM):
            moveSlide(on: edge, deltaMM: deltaMM)
        case .slideEnded(let edge):
            log.notice("slide ended on \(edge.rawValue, privacy: .public) edge")
            endSlide()
        case .mediaSwipe(let forward):
            let next = forward != prefs.settings.reverseMediaSwipe
            (next ? MediaKey.next : MediaKey.previous).post()
            haptics.bump(on: device.multitouchID)
        case .doubleTap(let zone):
            log.notice("double-tap in \(zone.rawValue, privacy: .public)")
            run(prefs.settings.tapAction(for: zone), device: device)
        }
    }

    private func beginSlide(on edge: Side, device: TrackpadDevice) {
        let action = prefs.settings.action(for: edge)
        guard action != .off, let start = currentValue(of: action) else {
            log.error("slide on \(edge.rawValue, privacy: .public) edge has no readable level for \(action.rawValue, privacy: .public)")
            return
        }
        slide = Slide(edge: edge, action: action, accumulator: StepAccumulator(start: start), deviceID: device.multitouchID,
                      muted: action == .volume && Volume.isMuted, detent: Self.detent(of: start))
        model.activeEdge = edge
        if prefs.settings.freezePointer, model.accessibilityGranted {
            pointer.freeze(at: pointerAnchor ?? PointerControl.location)
        }
    }

    private func moveSlide(on edge: Side, deltaMM: Double) {
        guard var current = slide, current.edge == edge else { return }
        let fine = isFineControlHeld
        let stepSize = prefs.settings.stepSize
        let steps = fine ? max(stepSize.steps, 64) : stepSize.steps
        var delta = deltaMM / fullRangeTravelMM * prefs.settings.sensitivity
        if fine { delta /= 4 }
        guard let value = current.accumulator.apply(delta: delta, steps: steps) else {
            slide = current
            return
        }
        set(current.action, to: value, slide: &current)

        // Smooth slides tick at every sixteenth, like the keyboard; stepped slides tick every step.
        let detent = Self.detent(of: value)
        if value == 0 || value == 1 {
            haptics.bump(on: current.deviceID)
        } else if stepSize != .smooth || fine || detent != current.detent {
            haptics.tick(on: current.deviceID)
        }
        current.detent = detent
        slide = current

        hud.show(HUDContent(action: current.action, value: value, muted: current.action == .volume && value == 0),
                 on: edge, steps: steps == 16 ? 16 : 64)
    }

    private static func detent(of value: Double) -> Int { Int((value * 16).rounded(.down)) }

    private func endSlide() {
        guard slide != nil || pointer.isFrozen else { return }
        slide = nil
        model.activeEdge = nil
        pointer.unfreeze()
    }

    private var isFineControlHeld: Bool {
        guard prefs.settings.fineControl else { return false }
        let flags = CGEventSource.flagsState(.combinedSessionState)
        return flags.contains(.maskShift) && flags.contains(.maskAlternate)
    }

    private func currentValue(of action: EdgeAction) -> Double? {
        switch action {
        case .brightness: return Brightness.get()
        case .volume: return Volume.get()
        case .keyboardBacklight: return KeyboardLight.get()
        case .off: return nil
        }
    }

    private func set(_ action: EdgeAction, to value: Double, slide: inout Slide) {
        switch action {
        case .brightness:
            if !Brightness.set(value) { log.error("could not set brightness") }
            model.brightness = value
        case .volume:
            Volume.set(value)
            // Like the keyboard: reaching zero mutes, moving up again unmutes.
            let shouldMute = value == 0
            if slide.muted != shouldMute {
                Volume.setMuted(shouldMute)
                slide.muted = shouldMute
            }
            model.volume = value
            model.muted = shouldMute
        case .keyboardBacklight:
            KeyboardLight.set(value)
            model.keyboardLight = value
        case .off:
            break
        }
    }

    private func run(_ action: TapAction, device: TrackpadDevice) {
        guard action != .none else { return }
        haptics.bump(on: device.multitouchID)
        if action == .mute {
            let muted = !Volume.isMuted
            Volume.setMuted(muted)
            model.muted = muted
            hud.show(HUDContent(action: .volume, value: Volume.get() ?? 0, muted: muted), on: .right, steps: 16)
            return
        }
        if let message = ActionRunner.run(action) {
            hud.toast(message, symbol: action.symbol)
        }
    }
}
