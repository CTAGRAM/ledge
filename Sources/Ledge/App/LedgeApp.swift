import AppKit
import SwiftUI

struct LedgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuRootView(prefs: .shared, model: .shared, actions: delegate.actions)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = EdgeController()
    private var setupWindow: NSWindow?
    private var sectionsWindow: NSWindow?

    lazy var actions = AppActions(
        requestAccessibility: { [weak self] in self?.requestAccessibility() },
        showSetup: { [weak self] in self?.showSetup() },
        showAbout: { [weak self] in self?.showAbout() },
        showSections: { [weak self] in self?.showSections() })

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
        if CommandLine.arguments.contains("--preview-menu") {
            showMenuPreview()
            showSections()
        } else if !Preferences.shared.settings.hasSeenSetup || !AXIsProcessTrusted() {
            showSetup()
        }
    }

    /// Debug aid: shows both menu pages in ordinary windows so they can be screenshotted.
    private var previewWindows: [NSWindow] = []
    private func showMenuPreview() {
        for (index, settingsPage) in [false, true].enumerated() {
            let view = MenuRootView(prefs: .shared, model: .shared, actions: actions, showingSettings: settingsPage)
            let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
            window.title = settingsPage ? "Ledge Settings Preview" : "Ledge Menu Preview"
            window.contentView = NSHostingView(rootView: view)
            window.setFrameTopLeftPoint(NSPoint(x: 80 + CGFloat(index) * 380, y: (NSScreen.main?.visibleFrame.maxY ?? 900) - 20))
            window.orderFrontRegardless()
            previewWindows.append(window)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }

    private func requestAccessibility() {
        controller.checkAccessibility(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func showSetup() {
        if let setupWindow {
            setupWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SetupView(prefs: .shared, model: .shared,
                             requestAccessibility: { [weak self] in self?.requestAccessibility() },
                             done: { [weak self] in self?.setupWindow?.close() })
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.center()
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            Preferences.shared.settings.hasSeenSetup = true
            self?.setupWindow = nil
        }
        setupWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showSections() {
        if sectionsWindow == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SectionsEditorView(prefs: .shared, model: .shared))
            window.center()
            sectionsWindow = window
        }
        sectionsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(
                string: "Free and open source. Turns your trackpad's edges into volume, brightness and media controls.",
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]),
        ])
    }
}

/// Menu bar glyph: a trackpad outline with a lit bar on each side.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 20, height: 15), flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1.5), xRadius: 3, yRadius: 3)
            outline.lineWidth = 1.4
            outline.stroke()
            NSBezierPath(roundedRect: NSRect(x: 4, y: 4, width: 2, height: 5), xRadius: 1, yRadius: 1).fill()
            NSBezierPath(roundedRect: NSRect(x: 14, y: 4, width: 2, height: 7), xRadius: 1, yRadius: 1).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
