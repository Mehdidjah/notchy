import SwiftUI

/// The update rows for Settings → About. Returns a `Section`, so embed it inside a `Form`.
struct UpdateSettingsSection: View {
    @ObservedObject private var checker: UpdateChecker

    init(checker: UpdateChecker = .shared) {
        _checker = ObservedObject(wrappedValue: checker)
    }

    var body: some View {
        Section("Updates") {
            Toggle("Check for updates automatically", isOn: $checker.automaticallyChecks)
                .disabled(checker.status == .unavailable)
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    if checker.isChecking { ProgressView().controlSize(.small) }
                    Text(statusText).foregroundStyle(.secondary)
                }
            }
            if let release = checker.availableRelease {
                HStack {
                    Button("Download Notchy \(release.version)") { checker.openDownload(release) }
                        .buttonStyle(.borderedProminent)
                    Button("Release Notes") { checker.openReleasePage(release) }
                }
                if !release.notes.isEmpty {
                    Text(release.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(8)
                }
            }
            Button("Check Now") { Task { await checker.checkNow() } }
                .disabled(checker.status == .unavailable || checker.isChecking)
            Text("Notchy looks for a new version every 30 minutes and tells you once when one is out. Open the downloaded disk image and drag Notchy into Applications to replace this copy.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        switch checker.status {
        case .unavailable: "Not available in this build"
        case .idle: lastCheckedText ?? "Not checked yet"
        case .checking: "Checking…"
        case .upToDate: "Up to date" + (lastCheckedText.map { " · \($0)" } ?? "")
        case .available(let release): "Notchy \(release.version) is available"
        case .failed(let message): message
        }
    }

    private var lastCheckedText: String? {
        checker.lastChecked.map { "Checked \($0.formatted(.relative(presentation: .named)))" }
    }
}
