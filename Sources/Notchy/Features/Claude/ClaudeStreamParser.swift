import Foundation

/// What one reply from Claude Code amounts to, event by event.
enum ClaudeStreamEvent: Equatable, Sendable {
    /// The run is up; `sessionID` is the conversation to resume on the next turn.
    case started(sessionID: String, model: String?)
    /// More of the reply's text, to append.
    case text(String)
    /// The plan's usage limits as of this reply.
    case planUsage(ClaudePlanUsage)
    /// The context window of each model the run used, by model ID.
    case contextWindows([String: Int])
    /// The reply is over. `errorMessage` is set when Claude Code reported a failure.
    case finished(sessionID: String?, errorMessage: String?)
}

/// Turns the lines Claude Code prints with `--output-format stream-json` into `ClaudeStreamEvent`s.
///
/// Text arrives as partial deltas (`--include-partial-messages`); the complete assistant message
/// that follows repeats it and is only used when no delta came, so the text is never doubled.
/// Lines it doesn't understand are skipped.
struct ClaudeStreamParser {
    /// Deltas seen since the current message started.
    private var sawDeltaInMessage = false
    /// Some text has been handed out in this run.
    private var hasEmittedText = false
    /// A block or message ended after some text, so the next text starts a new paragraph.
    private var needsParagraphBreak = false

    mutating func consume(_ line: String) -> [ClaudeStreamEvent] {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { return [] }

        switch type {
        case "system":
            guard object["subtype"] as? String == "init",
                  let sessionID = object["session_id"] as? String else { return [] }
            return [.started(sessionID: sessionID, model: object["model"] as? String)]

        case "stream_event":
            guard let event = object["event"] as? [String: Any] else { return [] }
            return consumeStreamEvent(event)

        case "assistant":
            // The finished message. Only needed when its deltas didn't arrive.
            guard !sawDeltaInMessage,
                  let message = object["message"] as? [String: Any],
                  let blocks = message["content"] as? [[String: Any]] else { return [] }
            let text = blocks
                .filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n\n")
            guard !text.isEmpty else { return [] }
            return emit(text)

        case "rate_limit_event":
            guard let info = object["rate_limit_info"] as? [String: Any],
                  let usage = ClaudePlanUsage.parseRateLimitEvent(info, receivedAt: Date()) else { return [] }
            return [.planUsage(usage)]

        case "result":
            var events: [ClaudeStreamEvent] = []
            if let models = object["modelUsage"] as? [String: Any] {
                let windows = models.compactMapValues { (($0 as? [String: Any])?["contextWindow"] as? NSNumber)?.intValue }
                if !windows.isEmpty { events.append(.contextWindows(windows)) }
            }
            return events + finish(object)

        default:
            return []
        }
    }

    private func finish(_ object: [String: Any]) -> [ClaudeStreamEvent] {
        let sessionID = object["session_id"] as? String
        let isError = object["is_error"] as? Bool ?? false
        let subtype = object["subtype"] as? String ?? "success"
        guard isError || subtype != "success" else {
            return [.finished(sessionID: sessionID, errorMessage: nil)]
        }
        let reason = (object["result"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? Self.describe(subtype: subtype)
        return [.finished(sessionID: sessionID, errorMessage: reason)]
    }

    private mutating func consumeStreamEvent(_ event: [String: Any]) -> [ClaudeStreamEvent] {
        switch event["type"] as? String {
        case "message_start":
            sawDeltaInMessage = false
            if hasEmittedText { needsParagraphBreak = true }
            return []
        case "content_block_stop":
            if hasEmittedText { needsParagraphBreak = true }
            return []
        case "content_block_delta":
            guard let delta = event["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String, !text.isEmpty else { return [] }
            sawDeltaInMessage = true
            return emit(text)
        default:
            return []
        }
    }

    private mutating func emit(_ text: String) -> [ClaudeStreamEvent] {
        let events: [ClaudeStreamEvent] = needsParagraphBreak && hasEmittedText ? [.text("\n\n"), .text(text)] : [.text(text)]
        needsParagraphBreak = false
        hasEmittedText = true
        return events
    }

    private static func describe(subtype: String) -> String {
        switch subtype {
        case "error_max_turns": "Claude stopped before finishing the reply."
        case "error_during_execution": "Claude Code ran into an error."
        default: "Claude Code couldn't finish the reply (\(subtype))."
        }
    }
}
