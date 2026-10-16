import Foundation
import SwiftData

enum DuplicateCaptureBehavior: String, Codable, CaseIterable, Sendable {
    case moveOriginalToFront
    case storeSeparateEvent
}

struct RetentionPolicy: Sendable, Equatable {
    var maximumAge: TimeInterval?
    var maximumItemCount: Int?
    var maximumDiskBytes: Int64?

    static let forever = RetentionPolicy(
        maximumAge: nil,
        maximumItemCount: nil,
        maximumDiskBytes: nil
    )
}

protocol ClipRepository: Sendable {
    func fetchAll(limit: Int?) async throws -> [Clip]
    func clip(id: UUID) async throws -> Clip?
    func save(_ clip: Clip, duplicateBehavior: DuplicateCaptureBehavior) async throws -> Clip
    func replace(_ clip: Clip) async throws
    func delete(ids: Set<UUID>) async throws
    func clearHistory(preservingProtected: Bool) async throws
    func applyRetention(_ policy: RetentionPolicy) async throws -> [Clip]
}

@MainActor
final class SwiftDataClipRepository: ClipRepository {
    private let container: ModelContainer
    private let context: ModelContext

    init(container: ModelContainer) {
        self.container = container
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    static func production() throws -> SwiftDataClipRepository {
        let schema = Schema([ClipRecord.self])
        let configuration = ModelConfiguration(
            "Notchy",
            schema: schema,
            url: try AppPaths.metadataStoreURL()
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return SwiftDataClipRepository(container: container)
    }

    static func inMemory() throws -> SwiftDataClipRepository {
        let schema = Schema([ClipRecord.self])
        let configuration = ModelConfiguration(
            "NotchyTests",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return SwiftDataClipRepository(container: container)
    }

    func fetchAll(limit: Int? = nil) throws -> [Clip] {
        var descriptor = FetchDescriptor<ClipRecord>(
            sortBy: [SortDescriptor(\ClipRecord.lastCopiedAt, order: .reverse)]
        )
        if let limit { descriptor.fetchLimit = limit }
        return try context.fetch(descriptor).map { $0.value() }
    }

    func clip(id: UUID) throws -> Clip? {
        try record(id: id)?.value()
    }

    func save(
        _ clip: Clip,
        duplicateBehavior: DuplicateCaptureBehavior = .moveOriginalToFront
    ) throws -> Clip {
        if duplicateBehavior == .moveOriginalToFront,
           let duplicate = try record(contentHash: clip.contentHash) {
            var merged = duplicate.value()
            merged.updatedAt = clip.updatedAt
            merged.lastCopiedAt = clip.lastCopiedAt
            merged.copyCount += 1
            merged.sourceApplicationBundleIdentifier = clip.sourceApplicationBundleIdentifier
            merged.sourceApplicationName = clip.sourceApplicationName
            merged.sourceApplicationIconReference = clip.sourceApplicationIconReference
            duplicate.update(from: merged)
            try context.save()
            return merged
        }

        context.insert(ClipRecord(clip: clip))
        try context.save()
        return clip
    }

    func replace(_ clip: Clip) throws {
        if let existing = try record(id: clip.id) {
            existing.update(from: clip)
        } else {
            context.insert(ClipRecord(clip: clip))
        }
        try context.save()
    }

    func delete(ids: Set<UUID>) throws {
        let records = try context.fetch(FetchDescriptor<ClipRecord>())
        for record in records where ids.contains(record.id) {
            context.delete(record)
        }
        try context.save()
    }

    func clearHistory(preservingProtected: Bool) throws {
        let records = try context.fetch(FetchDescriptor<ClipRecord>())
        for record in records {
            let protected = record.isFavorite || record.isPinned || record.isManuallySaved
            if !preservingProtected || !protected {
                context.delete(record)
            }
        }
        try context.save()
    }

    @discardableResult
    func applyRetention(_ policy: RetentionPolicy) throws -> [Clip] {
        let records = try context.fetch(FetchDescriptor<ClipRecord>(
            sortBy: [SortDescriptor(\ClipRecord.lastCopiedAt, order: .reverse)]
        ))
        let cutoff = policy.maximumAge.map { Date().addingTimeInterval(-$0) }
        var accumulatedBytes: Int64 = 0
        var retainedCount = 0
        var deleted: [Clip] = []

        for record in records {
            let protected = record.isFavorite || record.isPinned || record.isManuallySaved
            accumulatedBytes += max(0, record.byteSize)
            retainedCount += 1

            let isExpired = cutoff.map { record.lastCopiedAt < $0 } ?? false
            let exceedsCount = policy.maximumItemCount.map { retainedCount > $0 } ?? false
            let exceedsDisk = policy.maximumDiskBytes.map { accumulatedBytes > $0 } ?? false
            if !protected && (isExpired || exceedsCount || exceedsDisk) {
                deleted.append(record.value())
                context.delete(record)
            }
        }
        if !deleted.isEmpty { try context.save() }
        return deleted
    }

    private func record(id: UUID) throws -> ClipRecord? {
        try context.fetch(FetchDescriptor<ClipRecord>()).first { $0.id == id }
    }

    private func record(contentHash: String) throws -> ClipRecord? {
        try context.fetch(FetchDescriptor<ClipRecord>()).first { $0.contentHash == contentHash }
    }
}

actor InMemoryClipRepository: ClipRepository {
    private var clips: [Clip]

    init(clips: [Clip] = []) {
        self.clips = clips.sorted { $0.lastCopiedAt > $1.lastCopiedAt }
    }

    func fetchAll(limit: Int?) -> [Clip] {
        let sorted = clips.sorted { $0.lastCopiedAt > $1.lastCopiedAt }
        guard let limit else { return sorted }
        return Array(sorted.prefix(limit))
    }

    func clip(id: UUID) -> Clip? {
        clips.first { $0.id == id }
    }

    func save(_ clip: Clip, duplicateBehavior: DuplicateCaptureBehavior) -> Clip {
        if duplicateBehavior == .moveOriginalToFront,
           let index = clips.firstIndex(where: { $0.contentHash == clip.contentHash }) {
            clips[index].copyCount += 1
            clips[index].updatedAt = clip.updatedAt
            clips[index].lastCopiedAt = clip.lastCopiedAt
            clips[index].sourceApplicationBundleIdentifier = clip.sourceApplicationBundleIdentifier
            clips[index].sourceApplicationName = clip.sourceApplicationName
            return clips[index]
        }
        clips.append(clip)
        return clip
    }

    func replace(_ clip: Clip) {
        if let index = clips.firstIndex(where: { $0.id == clip.id }) {
            clips[index] = clip
        } else {
            clips.append(clip)
        }
    }

    func delete(ids: Set<UUID>) {
        clips.removeAll { ids.contains($0.id) }
    }

    func clearHistory(preservingProtected: Bool) {
        clips.removeAll {
            !preservingProtected || !($0.isFavorite || $0.isPinned || $0.isManuallySaved)
        }
    }

    func applyRetention(_ policy: RetentionPolicy) -> [Clip] {
        let cutoff = policy.maximumAge.map { Date().addingTimeInterval(-$0) }
        let ordered = clips.sorted { $0.lastCopiedAt > $1.lastCopiedAt }
        var accumulatedBytes: Int64 = 0
        var deleted: [Clip] = []
        var kept: [Clip] = []
        for (index, clip) in ordered.enumerated() {
            accumulatedBytes += max(0, clip.byteSize)
            let protected = clip.isFavorite || clip.isPinned || clip.isManuallySaved
            let expired = cutoff.map { clip.lastCopiedAt < $0 } ?? false
            let overCount = policy.maximumItemCount.map { index >= $0 } ?? false
            let overDisk = policy.maximumDiskBytes.map { accumulatedBytes > $0 } ?? false
            if !protected && (expired || overCount || overDisk) {
                deleted.append(clip)
            } else {
                kept.append(clip)
            }
        }
        clips = kept
        return deleted
    }
}
