import AppKit
import Combine
import SwiftUI

/// Tracks whether a Focus mode is on and which one (Atoll's DoNotDisturbManager).
///
/// Sources, all public: the Focus on/off distributed notifications; the Focus database polled
/// every 2 s when Full Disk Access has been granted (never requested automatically); and,
/// when chosen, a unified-log tail. Mode metadata from any source is reconciled here.
@MainActor
final class FocusMonitor: ObservableObject {
    static let shared = FocusMonitor()

    @Published private(set) var isMonitoring = false
    @Published private(set) var isActive = false
    @Published private(set) var modeIdentifier = ""
    @Published private(set) var modeName = ""
    /// Bumped when the mode changes while Focus stays on, so the toast can replay.
    @Published private(set) var toastTrigger = UUID()
    /// True for 2.5 s after Focus turns off in toast mode, while the "Off" toast plays.
    @Published private(set) var isToastDismissing = false
    @Published private(set) var hasFullDiskAccess = false
    @Published private(set) var modeConfigurations: [FocusModeConfiguration] = []

    let settings: FocusSettings

    private var observer: FocusNotificationObserver?
    private var poller: FocusDatabasePoller?
    private var logStream: FocusLogStream?
    private var metadataClearTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private var isFeatureStarted = false

    static let metadataRetention: Duration = .seconds(2)
    static let toastDismissDuration: Duration = .milliseconds(2_500)

    init(settings: FocusSettings = .shared) {
        self.settings = settings
        settings.$enableDoNotDisturbDetection
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self, self.isFeatureStarted else { return }
                if enabled { self.startMonitoring() } else { self.stopMonitoring() }
            }
            .store(in: &cancellables)
        settings.$monitoringMode
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] mode in self?.applyMonitoringMode(mode) }
            .store(in: &cancellables)
    }

    // MARK: - Derived

    var modeKind: FocusModeKind {
        FocusModeKind.resolve(identifier: modeIdentifier, name: modeName)
    }

    var appearance: FocusAppearance {
        let kind = modeKind
        let configuration = kind == .custom
            ? FocusDatabase.configuration(in: modeConfigurations, identifier: modeIdentifier, name: modeName)
            : nil
        return FocusAppearance(kind: kind, configuration: configuration)
    }

    // MARK: - Lifecycle

    func start() {
        isFeatureStarted = true
        if settings.enableDoNotDisturbDetection { startMonitoring() }
    }

    func stop() {
        isFeatureStarted = false
        stopMonitoring()
    }

    /// Re-checks Full Disk Access and re-reads the database, for a "Check Again" button.
    func refreshAccess() {
        if let poller {
            poller.refreshNow()
        } else {
            hasFullDiskAccess = FocusDatabase.hasFullDiskAccess()
        }
    }

    private func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        observer = FocusNotificationObserver { [weak self] event in
            Self.onMain { self?.handle(event) }
        }
        let poller = FocusDatabasePoller(callbacks: .init(
            access: { [weak self] granted in Self.onMain { self?.hasFullDiskAccess = granted } },
            assertions: { [weak self] reading in
                Self.onMain { self?.apply(metadata: FocusMetadata(identifier: reading.identifier, name: reading.name), isActive: reading.isActive) }
            },
            configurations: { [weak self] configurations in
                Self.onMain { self?.modeConfigurations = configurations }
            }
        ))
        self.poller = poller
        applyMonitoringMode(settings.monitoringMode)
    }

    private func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        observer?.invalidate()
        observer = nil
        poller?.stop()
        poller = nil
        logStream?.stop()
        logStream = nil
        metadataClearTask?.cancel()
        toastDismissTask?.cancel()
        isToastDismissing = false
        if isActive { withAnimation(.smooth(duration: 0.25)) { isActive = false } }
        modeIdentifier = ""
        modeName = ""
    }

    private func applyMonitoringMode(_ mode: FocusMonitoringMode) {
        guard isMonitoring else { return }
        switch mode {
        case .standard:
            logStream?.stop()
            logStream = nil
            poller?.start(readsAssertions: true)
        case .unifiedLog:
            // The database is still read for custom-mode names, glyphs and colours.
            poller?.start(readsAssertions: false)
            guard logStream == nil else { return }
            let stream = FocusLogStream(
                onEvent: { [weak self] event in
                    Self.onMain {
                        switch event {
                        case .cleared: break
                        case let .metadata(metadata): self?.apply(metadata: metadata, isActive: nil)
                        }
                    }
                },
                onInitialMode: { [weak self] metadata in
                    Self.onMain { self?.apply(metadata: metadata, isActive: true) }
                }
            )
            logStream = stream
            stream.start()
        }
    }

    // MARK: - Events

    private func handle(_ event: FocusNotificationEvent) {
        poller?.noteNotification()
        apply(metadata: event.metadata, isActive: event.isActive)
    }

    /// Reconciles one report. `isActive == nil` means metadata only (the log stream).
    func apply(metadata: FocusMetadata, isActive reportedActive: Bool?) {
        let rawIdentifier = metadata.identifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawName = metadata.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let identifier = (rawIdentifier?.isEmpty == false && rawIdentifier?.lowercased() != "com.apple.focus")
            ? rawIdentifier : nil
        let name = rawName?.isEmpty == false ? rawName : nil

        let wasActive = isActive
        let previousIdentifier = modeIdentifier
        let previousName = modeName

        guard identifier != nil || name != nil else {
            // No metadata: change the state only, keeping any mode already known.
            guard let reportedActive, reportedActive != wasActive else { return }
            if reportedActive, previousIdentifier.isEmpty {
                modeIdentifier = FocusModeKind.doNotDisturb.rawValue
                modeName = FocusModeKind.doNotDisturb.displayName
            }
            setActive(reportedActive)
            return
        }

        let kind = FocusModeKind.resolve(identifier: identifier, name: name)
        let finalIdentifier = identifier ?? kind.rawValue
        var finalName = displayName(for: kind, name: name, identifier: finalIdentifier)
        if finalName.localizedCaseInsensitiveContains("Reduce Interruptions") { finalName = "Reduce Interr." }

        let identifierChanged = finalIdentifier != previousIdentifier
        if identifierChanged { modeIdentifier = finalIdentifier }
        if finalName != previousName { modeName = finalName }

        // A different mode while Focus stays on replays the toast for the new mode.
        if wasActive, reportedActive != false, identifierChanged, !previousIdentifier.isEmpty {
            toastTrigger = UUID()
        }

        guard let reportedActive, reportedActive != wasActive else { return }
        if !reportedActive {
            // Keep showing the mode that just ended while the "off" animation plays.
            modeIdentifier = previousIdentifier.isEmpty ? finalIdentifier : previousIdentifier
            modeName = previousName.isEmpty ? finalName : previousName
        }
        setActive(reportedActive)
    }

    private func displayName(for kind: FocusModeKind, name: String?, identifier: String) -> String {
        if kind == .custom {
            if hasFullDiskAccess,
               let configured = FocusDatabase.configuration(in: modeConfigurations, identifier: identifier, name: name) {
                return configured.name
            }
            // A dotted name is a symbol slug ("graduationcap.fill"), not a display name.
            if let name, !name.contains(".") { return name }
            return "Focus"
        }
        if let name { return FocusModeKind.normalizedName(name) }
        return kind.displayName.isEmpty ? "Focus" : kind.displayName
    }

    private func setActive(_ active: Bool) {
        withAnimation(.smooth(duration: 0.25)) { isActive = active }
        if active {
            metadataClearTask?.cancel()
            metadataClearTask = nil
            toastDismissTask?.cancel()
            toastDismissTask = nil
            isToastDismissing = false
        } else {
            scheduleMetadataClear()
            beginToastDismissIfNeeded()
        }
    }

    private func scheduleMetadataClear() {
        metadataClearTask?.cancel()
        metadataClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.metadataRetention)
            guard !Task.isCancelled, let self, !self.isActive else { return }
            self.modeIdentifier = ""
            self.modeName = ""
        }
    }

    private func beginToastDismissIfNeeded() {
        guard settings.focusIndicatorNonPersistent else { return }
        toastDismissTask?.cancel()
        isToastDismissing = true
        toastDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.toastDismissDuration)
            guard !Task.isCancelled, let self else { return }
            withAnimation(.smooth(duration: 0.25)) { self.isToastDismissing = false }
        }
    }

    nonisolated private static func onMain(_ work: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated { work() } }
    }

    // MARK: - System Settings

    /// Opens Privacy & Security > Full Disk Access. Only ever called from a button.
    static func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }
}
