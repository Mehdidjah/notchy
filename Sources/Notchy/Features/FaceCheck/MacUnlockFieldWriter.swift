import Foundation

/// Only non-content readback is exposed. A missing count means the attribute is
/// explicitly unsupported; transport errors must throw instead of selecting a fallback.
@MainActor
struct MacUnlockFieldAccess {
    var validate: () throws -> Void
    var count: () throws -> Int?
    var selection: () throws -> Range<Int>?
    /// True only after the field acknowledges replacing its complete value with empty text.
    var replaceWithEmptyValue: () throws -> Bool
    var clearWithEditingKeys: () async throws -> Void
    var typeBatch: (Range<Int>) async throws -> Void
    var pressReturn: () async throws -> Void
}

/// Secure text fields can intentionally omit their character count. In that case,
/// establish an empty field with an acknowledged replacement, then require a collapsed
/// selection to advance by each batch's UTF-16 length. Never read AXValue or selected text.
@MainActor
struct MacUnlockFieldWriter {
    private enum Readback {
        case count, selectionAfterReplacement
    }

    let access: MacUnlockFieldAccess

    func write(_ plan: MacUnlockPasswordPlan) async throws {
        try access.validate()
        let readback: Readback
        if let count = try access.count() {
            guard count >= 0 else { throw MacUnlockPlatformError.fieldCannotBeCleared }
            readback = .count
            if count != 0 {
                try access.validate()
                if try !access.replaceWithEmptyValue() {
                    try access.validate()
                    try await access.clearWithEditingKeys()
                }
                try await awaitPosition(0, using: readback, failure: .fieldCannotBeCleared)
            }
        } else {
            // A collapsed selection alone cannot prove an unknown field is empty.
            // This path therefore requires successful whole-field replacement first.
            guard try access.selection() != nil else { throw MacUnlockPlatformError.fieldCannotBeCleared }
            try access.validate()
            guard try access.replaceWithEmptyValue() else { throw MacUnlockPlatformError.fieldCannotBeCleared }
            readback = .selectionAfterReplacement
            try await awaitPosition(0, using: readback, failure: .fieldCannotBeCleared)
        }

        for step in plan.steps {
            switch step {
            case .clearFocusedField: continue // Completed above, before any text event.
            case .unicode(let range):
                try access.validate()
                guard try positionMatches(range.lowerBound, using: readback) else {
                    throw MacUnlockPlatformError.inputNotAccepted
                }
                try await access.typeBatch(range)
                try await awaitPosition(range.upperBound, using: readback, failure: .inputNotAccepted)
            case .submitReturn:
                try access.validate()
                guard try positionMatches(plan.unitCount, using: readback) else {
                    throw MacUnlockPlatformError.inputNotAccepted
                }
                try await access.pressReturn()
            }
        }
    }

    private func positionMatches(_ expected: Int, using readback: Readback) throws -> Bool {
        switch readback {
        case .count:
            guard let count = try access.count() else { throw MacUnlockPlatformError.inputNotAccepted }
            return count == expected
        case .selectionAfterReplacement:
            guard let selection = try access.selection() else { throw MacUnlockPlatformError.inputNotAccepted }
            return selection.isEmpty && selection.lowerBound == expected
        }
    }

    private func awaitPosition(_ expected: Int, using readback: Readback, failure: MacUnlockPlatformError) async throws {
        for _ in 0..<10 {
            try access.validate()
            if try positionMatches(expected, using: readback) { return }
            try await Task.sleep(for: .milliseconds(15))
        }
        throw failure
    }
}
