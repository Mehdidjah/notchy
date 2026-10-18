import Foundation

/// A release version such as `1.4.2`, `v1.5` or `2.0.0-beta.1`.
///
/// Missing components count as zero, so `1.2` equals `1.2.0`. A pre-release sorts before the
/// release it leads up to. Build metadata after `+` is ignored.
struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    let components: [Int]
    let prerelease: String?

    init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        if let plus = text.firstIndex(of: "+") { text = String(text[..<plus]) }

        var prerelease: String?
        if let dash = text.firstIndex(of: "-") {
            prerelease = String(text[text.index(after: dash)...])
            text = String(text[..<dash])
            guard prerelease?.isEmpty == false else { return nil }
        }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 4 else { return nil }
        var components: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isASCII), let value = Int(part), value >= 0 else { return nil }
            components.append(value)
        }
        self.components = components
        self.prerelease = prerelease
    }

    var description: String {
        components.map(String.init).joined(separator: ".") + (prerelease.map { "-\($0)" } ?? "")
    }

    /// Components without trailing zeros, so equal versions compare and hash the same.
    private var significantComponents: ArraySlice<Int> {
        var slice = components[...]
        while slice.count > 1, slice.last == 0 { slice = slice.dropLast() }
        return slice
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.significantComponents == rhs.significantComponents && lhs.prerelease == rhs.prerelease
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(Array(significantComponents))
        hasher.combine(prerelease)
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil), (nil, _?): return false
        case (_?, nil): return true
        case let (left?, right?): return left.compare(right, options: .numeric) == .orderedAscending
        }
    }
}
