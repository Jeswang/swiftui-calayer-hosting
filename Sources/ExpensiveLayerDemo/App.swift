import SwiftUI
import AppKit

/// Forces a proper foreground GUI app even when launched via `swift run`
/// (a bare SwiftPM executable is not a normal .app bundle).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct ExpensiveLayerDemoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("Expensive CALayer Hosting Demo") {
            ContentView()
        }
    }
}
