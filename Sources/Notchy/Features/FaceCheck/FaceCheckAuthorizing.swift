import Foundation

/// An in-app check. Completion grants one pending operation; callers must discard stale results.
@MainActor
protocol FaceCheckAuthorizing: AnyObject {
    func authorize(
        reason: String,
        requiresEnrollment: Bool,
        completion: @escaping @MainActor (Bool) -> Void
    )
    func cancelAuthorization()
}

extension FaceCheckAuthorizing {
    func cancelAuthorization() {}
}
