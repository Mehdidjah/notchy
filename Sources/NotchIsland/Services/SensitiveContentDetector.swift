import Foundation

enum SensitiveContentReason: String, CaseIterable, Codable, Sendable {
    case password
    case apiKey
    case accessToken
    case githubToken
    case awsCredential
    case jwt
    case privateKey
    case creditCard
    case environmentFile
    case databaseConnection
    case highEntropySecret
}

struct SensitiveContentResult: Equatable, Sendable {
    var reasons: Set<SensitiveContentReason>
    var isSensitive: Bool { !reasons.isEmpty }
}

struct SensitiveContentDetector: Sendable {
    func inspect(_ text: String) -> SensitiveContentResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return SensitiveContentResult(reasons: []) }

        var reasons: Set<SensitiveContentReason> = []
        let lowercased = trimmed.lowercased()

        if contains(pattern: "-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----", in: trimmed) {
            reasons.insert(.privateKey)
        }
        if contains(pattern: #"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b"#, in: trimmed) {
            reasons.insert(.jwt)
        }
        if contains(pattern: #"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{50,})\b"#, in: trimmed) {
            reasons.insert(.githubToken)
        }
        if contains(pattern: #"\bAKIA[0-9A-Z]{16}\b"#, in: trimmed)
            || contains(pattern: #"(?i)aws_secret_access_key\s*[:=]\s*[^\s]{24,}"#, in: trimmed) {
            reasons.insert(.awsCredential)
        }
        if contains(
            pattern: #"(?i)\b(?:password|passwd|pwd)\s*[:=]\s*['\"]?[^\s'\"]{6,}"#,
            in: trimmed
        ) {
            reasons.insert(.password)
        }
        if contains(
            pattern: #"(?i)\b(?:api[_-]?key|secret[_-]?key|client[_-]?secret)\s*[:=]\s*['\"]?[^\s'\"]{12,}"#,
            in: trimmed
        ) {
            reasons.insert(.apiKey)
        }
        if contains(
            pattern: #"(?i)\b(?:access[_-]?token|auth[_-]?token|bearer)\s*[:= ]\s*['\"]?[A-Za-z0-9._~+/-]{16,}"#,
            in: trimmed
        ) {
            reasons.insert(.accessToken)
        }
        if contains(pattern: #"(?im)^\s*[A-Z][A-Z0-9_]{2,}\s*=\s*[^\s#]{8,}\s*$"#, in: trimmed),
           lowercased.contains("secret") || lowercased.contains("token") || lowercased.contains("password") {
            reasons.insert(.environmentFile)
        }
        if contains(
            pattern: #"(?i)\b(?:postgres(?:ql)?|mysql|mongodb(?:\+srv)?|redis)://[^\s:@/]+:[^\s@/]+@"#,
            in: trimmed
        ) {
            reasons.insert(.databaseConnection)
        }
        if containsValidPaymentCard(in: trimmed) {
            reasons.insert(.creditCard)
        }
        if containsContextualHighEntropySecret(in: trimmed) {
            reasons.insert(.highEntropySecret)
        }

        return SensitiveContentResult(reasons: reasons)
    }

    private func contains(pattern: String, in text: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.firstMatch(in: text, range: range) != nil
    }

    private func containsValidPaymentCard(in text: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: #"(?<!\d)(?:\d[ -]?){13,19}(?!\d)"#) else {
            return false
        }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: fullRange).contains { match in
            guard let range = Range(match.range, in: text) else { return false }
            let digits = text[range].compactMap(\.wholeNumberValue)
            return (13...19).contains(digits.count) && luhnIsValid(digits)
        }
    }

    private func luhnIsValid(_ digits: [Int]) -> Bool {
        guard !Set(digits).isSubset(of: [0]) else { return false }
        let sum = digits.reversed().enumerated().reduce(0) { partial, pair in
            let (offset, digit) = pair
            guard offset.isMultiple(of: 2) == false else { return partial + digit }
            let doubled = digit * 2
            return partial + (doubled > 9 ? doubled - 9 : doubled)
        }
        return sum.isMultiple(of: 10)
    }

    private func containsContextualHighEntropySecret(in text: String) -> Bool {
        guard text.range(
            of: #"(?i)(secret|token|credential|private|api[_-]?key)"#,
            options: .regularExpression
        ) != nil else { return false }

        let candidates = text.split { $0.isWhitespace || "=:'\";,".contains($0) }
        return candidates.contains { candidate in
            guard candidate.count >= 28, candidate.count <= 256 else { return false }
            let alphabet = Set(candidate)
            guard alphabet.contains(where: \.isLowercase),
                  alphabet.contains(where: \.isUppercase),
                  alphabet.contains(where: \.isNumber)
            else { return false }

            let counts = Dictionary(grouping: candidate, by: { $0 }).mapValues(\.count)
            let length = Double(candidate.count)
            let entropy = counts.values.reduce(0.0) { total, count in
                let probability = Double(count) / length
                return total - probability * log2(probability)
            }
            return entropy >= 4.0
        }
    }
}
