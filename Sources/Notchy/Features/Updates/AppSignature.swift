import Foundation
import Security

/// How this copy of Notchy is signed, which decides whether macOS opens a downloaded update
/// straight away.
enum AppSignature {
    /// True when this copy is signed with a Developer ID. Releases signed that way are notarized,
    /// so macOS opens their updates without asking; other builds are refused on the first launch
    /// of each new version until the user clicks Open Anyway in System Settings.
    static let hasDeveloperID: Bool = {
        // A Developer ID Application certificate issued by Apple.
        let text = "anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
        var code: SecCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              let requirement else {
            return false
        }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }()

    /// How to install a downloaded update, with the Open Anyway step when macOS will ask for it.
    static func installInstructions(hasDeveloperID: Bool = hasDeveloperID) -> String {
        let install = "Open the downloaded disk image and drag Notchy into Applications to replace this copy."
        guard !hasDeveloperID else { return install }
        return install + " The first time you open the new version, macOS says it can't verify Notchy: click Done, then click Open Anyway in System Settings → Privacy & Security."
    }
}
