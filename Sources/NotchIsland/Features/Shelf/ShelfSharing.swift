import AppKit

/// Sends shelf items through AirDrop or the system share picker and reports when the share
/// has finished, so the island can be held open for the duration and scratch files removed.
@MainActor
final class ShelfSharingCoordinator: NSObject, NSSharingServiceDelegate, NSSharingServicePickerDelegate {
    static let shared = ShelfSharingCoordinator()

    /// Called when a share starts and when it ends; the shelf uses them to keep the island open.
    var onBegin: (() -> Void)?
    var onEnd: (() -> Void)?

    private(set) var isSharing = false
    private var completion: (() -> Void)?
    private var activePicker: NSSharingServicePicker?

    /// AirDrop accepts file and web URLs. Returns false when the service cannot take the items.
    @discardableResult
    func airDrop(_ objects: [Any], completion: (() -> Void)? = nil) -> Bool {
        guard !objects.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: objects) else { return false }
        begin(completion: completion)
        service.delegate = self
        service.perform(withItems: objects)
        return true
    }

    func presentPicker(_ objects: [Any], from view: NSView, preferredEdge: NSRectEdge = .minY, completion: (() -> Void)? = nil) {
        guard !objects.isEmpty else { return }
        begin(completion: completion)
        let picker = NSSharingServicePicker(items: objects)
        picker.delegate = self
        activePicker = picker
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: preferredEdge)
    }

    /// Routes to the configured target; the picker is the fallback when AirDrop declines.
    func share(_ objects: [Any], via target: ShelfShareTarget, from view: NSView?, completion: (() -> Void)? = nil) {
        switch target {
        case .airDrop:
            if airDrop(objects, completion: completion) { return }
            if let view { presentPicker(objects, from: view, completion: completion) } else { completion?() }
        case .shareMenu:
            if let view { presentPicker(objects, from: view, completion: completion) } else { completion?() }
        }
    }

    // MARK: NSSharingServiceDelegate

    nonisolated func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) {
        Task { @MainActor in self.finish() }
    }

    // MARK: NSSharingServicePickerDelegate

    nonisolated func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        let cancelled = service == nil
        Task { @MainActor in
            self.activePicker = nil
            if cancelled { self.finish() }
        }
    }

    nonisolated func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        delegateFor sharingService: NSSharingService
    ) -> (any NSSharingServiceDelegate)? {
        self
    }

    // MARK: Private

    private func begin(completion: (() -> Void)?) {
        if isSharing { finish() }
        isSharing = true
        self.completion = completion
        onBegin?()
    }

    private func finish() {
        guard isSharing else { return }
        isSharing = false
        let pending = completion
        completion = nil
        pending?()
        onEnd?()
    }
}
