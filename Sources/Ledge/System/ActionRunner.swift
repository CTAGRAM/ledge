import AppKit
import LedgeCore
import SwiftUI

/// Runs the action assigned to a tap section.
enum ActionRunner {
    /// Runs `action`; returns a short confirmation for the on-screen toast, or nil to show nothing.
    @discardableResult
    static func run(_ action: TapAction) -> String? {
        switch action {
        case .none, .mute:
            return nil // mute is handled by the controller, which owns the volume HUD
        case .playPause:
            MediaKey.playPause.post()
            return nil
        case .nextTrack:
            MediaKey.next.post()
            return nil
        case .previousTrack:
            MediaKey.previous.post()
            return nil
        case .missionControl:
            SystemActions.openMissionControl()
            return nil
        case .showDesktop:
            launch("/System/Applications/Mission Control.app/Contents/MacOS/Mission Control", ["1"])
            return nil
        case .lockScreen:
            SystemActions.lockScreen()
            return nil
        case .screenshot:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app"))
            return nil
        case .openApp(let path):
            guard !path.isEmpty else { return "No app chosen" }
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
            return "Opening \(appName(at: path))"
        case .runShortcut(let name):
            guard !name.isEmpty else { return "No shortcut chosen" }
            launch("/usr/bin/shortcuts", ["run", name])
            return "Running “\(name)”"
        case .openURL(let text):
            guard let url = url(from: text) else { return "Invalid link" }
            NSWorkspace.shared.open(url)
            return nil
        case .keyboardShortcut(let combo):
            guard !combo.display.isEmpty else { return "No keys recorded" }
            press(combo)
            return nil
        case .shellCommand(let command):
            guard !command.trimmingCharacters(in: .whitespaces).isEmpty else { return "No command set" }
            launch("/bin/zsh", ["-lc", command])
            return "Ran command"
        case .timer(let minutes):
            return TimerService.shared.toggle(minutes: minutes)
        }
    }

    static func appName(at path: String) -> String {
        FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
    }

    /// Accepts full URLs, bare domains and file paths.
    static func url(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
        }
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        return URL(string: "https://" + trimmed)
    }

    private static func press(_ combo: KeyCombo) {
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: isDown)
            event?.flags = CGEventFlags(rawValue: combo.modifiers)
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func launch(_ executable: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { NSLog("Ledge: could not run \(executable): \(error.localizedDescription)") }
    }
}

/// The user's shortcuts from the Shortcuts app.
enum ShortcutsLibrary {
    static func list(completion: @escaping ([String]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["list"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            var names: [String] = []
            if (try? process.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                names = String(decoding: data, as: UTF8.self)
                    .split(separator: "\n").map(String.init).filter { !$0.isEmpty }.sorted()
            }
            DispatchQueue.main.async { completion(names) }
        }
    }
}

// MARK: - Timer

/// A countdown started from a tap section. Double-tap again to cancel it.
final class TimerService {
    static let shared = TimerService()

    private var timer: DispatchSourceTimer?
    private var minutes = 0
    private var alert: NSPanel?
    private var sound: Timer?

    var isRunning: Bool { timer != nil }

    /// Starts a timer, or cancels the one that's running. Returns a confirmation message.
    func toggle(minutes: Int) -> String {
        if isRunning {
            cancel()
            return "Timer cancelled"
        }
        self.minutes = minutes
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + .seconds(max(1, minutes) * 60))
        source.setEventHandler { [weak self] in self?.finish() }
        source.resume()
        timer = source
        return "\(minutes)-minute timer started"
    }

    func cancel() {
        timer?.cancel()
        timer = nil
    }

    private func finish() {
        cancel()
        showAlert()
        var rings = 0
        NSSound(named: "Glass")?.play()
        sound = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: true) { [weak self] timer in
            rings += 1
            NSSound(named: "Glass")?.play()
            if rings >= 15 { timer.invalidate(); self?.sound = nil }
        }
    }

    private func showAlert() {
        let view = TimerAlertView(minutes: minutes) { [weak self] in self?.dismiss() }
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: view)
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.midX - host.fittingSize.width / 2, y: screen.maxY - host.fittingSize.height - 40))
        }
        panel.orderFrontRegardless()
        alert = panel
    }

    private func dismiss() {
        sound?.invalidate()
        sound = nil
        alert?.orderOut(nil)
        alert = nil
    }
}

private struct TimerAlertView: View {
    let minutes: Int
    let stop: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "alarm.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.orange)
                .symbolEffect(.pulse)
            VStack(alignment: .leading, spacing: 2) {
                Text("Time's up").font(.system(size: 15, weight: .semibold))
                Text("Your \(minutes)-minute timer has finished.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button("Stop", action: stop)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
        .padding(18)
        .frame(width: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.primary.opacity(0.1)))
        .padding(10)
    }
}
