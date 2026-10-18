import AppKit

/// Shows the result of an update check the user started from the menu bar.
@MainActor
enum UpdatePrompt {
    static func presentResult(of checker: UpdateChecker) {
        let alert = NSAlert()
        let current = checker.currentVersion?.description ?? "development"
        switch checker.status {
        case .available(let release):
            alert.messageText = "Notchy \(release.version) is available"
            alert.informativeText = "You have version \(current). Download the new version, open it, and drag Notchy into Applications to replace this copy."
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Later")
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn { checker.openDownload(release) }
            return
        case .upToDate:
            alert.messageText = "Notchy is up to date"
            alert.informativeText = "Version \(current) is the newest version."
        case .failed(let message):
            alert.messageText = "Couldn't check for updates"
            alert.informativeText = message
        case .unavailable:
            alert.messageText = "Updates aren't available in this build"
            alert.informativeText = "This copy was built without a version number or a release feed."
        case .idle, .checking:
            return
        }
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }
}
