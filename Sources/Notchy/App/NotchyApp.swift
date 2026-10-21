import AppKit

@main
enum NotchyApplication {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let appDelegate = AppDelegate()
        application.delegate = appDelegate
        application.setActivationPolicy(.accessory)

        withExtendedLifetime(appDelegate) {
            application.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Before anything reads settings or opens the clipboard store.
        LegacyDataMigration.run()
        do {
            let environment = try AppEnvironment()
            self.environment = environment
            environment.start()
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Notchy could not open its local clipboard store."
            alert.informativeText = "No clipboard data was uploaded or changed. \(error.localizedDescription)"
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Opening Notchy again while it runs (from the Dock, the Finder or Launchpad) opens the
    /// island: a menu-bar app has no window to bring back, so otherwise nothing would happen.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        environment?.showIsland()
        return false
    }
}
