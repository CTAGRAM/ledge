import AppKit
import LedgeCore
import LedgePrivate

enum Diagnostics {
    static func printReport() {
        let monitor = TrackpadMonitor.shared
        monitor.start()
        print("Trackpads: \(monitor.devices.count)")
        for device in monitor.devices {
            print(String(format: "  • family %d, %@, id 0x%llx, %.1f × %.1f mm",
                         device.familyID, device.isBuiltIn ? "built-in" : "external",
                         device.multitouchID, device.surface.widthMM, device.surface.heightMM))
        }
        monitor.stop()

        func percent(_ value: Double?) -> String { value.map { "\(Int(($0 * 100).rounded()))%" } ?? "unavailable" }
        print("Brightness: \(percent(Brightness.get())) (built-in display \(Brightness.builtInDisplay.map(String.init) ?? "none"))")
        print("Volume: \(percent(Volume.get()))\(Volume.isMuted ? " (muted)" : "")")
        print("Keyboard light: \(KeyboardLight.isAvailable ? percent(KeyboardLight.get()) : "unavailable")")
        print("Accessibility: \(AXIsProcessTrusted() ? "granted" : "not granted")")
    }

    /// Shows the system brightness and volume HUDs at their current levels without changing anything.
    static func hudTest() {
        let brightness = Brightness.get() ?? 0.5
        let volume = Volume.get() ?? 0.5
        let shown = LGShowSystemHUD(LGOSDImageBrightness, CGMainDisplayID(), UInt32((brightness * 64).rounded()), 64)
        print("System HUD available: \(shown)")
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        _ = LGShowSystemHUD(LGOSDImageSpeaker, CGMainDisplayID(), UInt32((volume * 16).rounded()), 16)
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    }
}
