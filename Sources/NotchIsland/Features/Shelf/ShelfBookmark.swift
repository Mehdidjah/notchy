import Foundation

/// A plain file bookmark. The app is not sandboxed, so security-scoped bookmarks are neither
/// available nor needed; a plain bookmark still follows the file through renames and moves.
struct ShelfBookmark: Sendable, Equatable {
    struct Resolution: Sendable {
        let url: URL
        /// Fresh bookmark data when the system reported the stored one as stale.
        let refreshedData: Data?
    }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(fileURL url: URL) throws {
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Resolves the bookmark, mounting a volume if it has to. Prefer `resolveInBackground()`
    /// from the main actor.
    func resolve() -> Resolution? {
        guard !data.isEmpty else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        let refreshed = isStale ? try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) : nil
        return Resolution(url: url, refreshedData: refreshed)
    }

    /// Safe on the main actor: never blocks on an unreachable network mount.
    func resolveWithoutMounting() -> URL? {
        guard !data.isEmpty else { return nil }
        var isStale = false
        return try? URL(resolvingBookmarkData: data, options: [.withoutMounting], relativeTo: nil, bookmarkDataIsStale: &isStale)
    }

    func resolveInBackground() async -> Resolution? {
        let data = self.data
        return await Task.detached(priority: .userInitiated) {
            ShelfBookmark(data: data).resolve()
        }.value
    }

    /// True when the file the bookmark points at still exists.
    func fileExists() async -> Bool {
        guard let resolution = await resolveInBackground() else { return false }
        let path = resolution.url.path
        return await Task.detached(priority: .utility) {
            FileManager.default.fileExists(atPath: path)
        }.value
    }
}
