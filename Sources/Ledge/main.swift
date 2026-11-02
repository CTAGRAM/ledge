import AppKit

// `Ledge --diagnose` prints what Ledge can see on this Mac; `--hud-test` flashes the system HUD.
if CommandLine.arguments.contains("--diagnose") {
    Diagnostics.printReport()
    exit(0)
}
if CommandLine.arguments.contains("--hud-test") {
    Diagnostics.hudTest()
    exit(0)
}

LedgeApp.main()
