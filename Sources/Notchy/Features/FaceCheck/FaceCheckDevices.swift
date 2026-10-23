@preconcurrency import AVFoundation
import AppKit
import Combine

struct FaceCheckDeviceOption: Identifiable, Equatable {
    let id: String
    let name: String
}

@MainActor
enum FaceCheckDisplay {
    static func identifier(_ screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return "" }
        return CFUUIDCreateString(nil, uuid) as String
    }

    static func isBuiltIn(_ screen: NSScreen?) -> Bool {
        guard let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
        return CGDisplayIsBuiltin(number.uint32Value) != 0
    }

    static func resolve(_ id: String) -> NSScreen? {
        if id == "builtin", let builtIn = NSScreen.screens.first(where: { isBuiltIn($0) }) { return builtIn }
        if let selected = NSScreen.screens.first(where: { identifier($0) == id }) { return selected }
        // The menu-bar display is stable even when a different window becomes key.
        return NSScreen.screens.first ?? NSScreen.main
    }

    static func cameraID(options: FaceCheckOptions) -> String {
        options.cameraID(forBuiltInDisplay: isBuiltIn(resolve(options.displayID)))
    }
}

@MainActor
final class FaceCheckDeviceCatalog: ObservableObject {
    @Published private(set) var cameras: [FaceCheckDeviceOption] = []
    @Published private(set) var displays: [FaceCheckDeviceOption] = []
    private var observations: [AnyCancellable] = []

    init() {
        refresh()
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification,
                     NSApplication.didChangeScreenParametersNotification] {
            NotificationCenter.default.publisher(for: name).receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.refresh() }.store(in: &observations)
        }
    }

    func refresh() {
        cameras = FaceCheckCamera.availableDevices().map { FaceCheckDeviceOption(id: $0.uniqueID, name: $0.localizedName) }
        displays = NSScreen.screens.map { FaceCheckDeviceOption(id: FaceCheckDisplay.identifier($0), name: $0.localizedName) }
    }
}
