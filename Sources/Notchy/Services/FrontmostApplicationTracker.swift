import AppKit

@MainActor
protocol PasteTargetProviding: AnyObject {
    func rememberFrontmostApplication()
    func targetApplication() -> NSRunningApplication?
}

@MainActor
final class FrontmostApplicationTracker: PasteTargetProviding {
    private var rememberedApplication: NSRunningApplication?

    func rememberFrontmostApplication() {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        rememberedApplication = application
    }

    func targetApplication() -> NSRunningApplication? {
        if let rememberedApplication, !rememberedApplication.isTerminated {
            return rememberedApplication
        }
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return application
    }
}
