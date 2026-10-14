//
//  AgentPartialReply.swift
//  Tenra
//
//  The reply's text while the model is still writing it (docs/plan-ai-assistant.md §3.7): the
//  server forwards `render_reply`'s input JSON piece by piece (event "reply"), and this reads the
//  text blocks written so far out of the unfinished JSON. The JSON is closed where it was cut (an
//  open string, the open arrays and objects) and parsed; a cut that leaves it unreadable (inside a
//  key, a number, an escape) yields nothing, and the screen keeps what it showed. Cards need their
//  whole block and come with the finished reply.
//

import Foundation

nonisolated enum AgentPartialReply {
    /// The text blocks of an unfinished `render_reply` input, in order; nil when the piece so far
    /// cannot be read.
    static func texts(fromPartialJSON partial: String) -> [String]? {
        guard let closed = closing(partial),
              let object = try? JSONSerialization.jsonObject(with: Data(closed.utf8)) as? [String: Any],
              let blocks = object["blocks"] as? [[String: Any]] else { return nil }
        return blocks.compactMap { block in
            guard block["type"] as? String == "text", let text = block["text"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return text
        }
    }

    /// The unfinished JSON closed where it was cut: the open string, then a dangling `,` or `:`
    /// taken care of, then the open arrays and objects in reverse.
    static func closing(_ partial: String) -> String? {
        var closers: [Character] = []
        var inString = false
        var escaped = false
        for character in partial {
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }
            switch character {
            case "\"": inString = true
            case "{": closers.append("}")
            case "[": closers.append("]")
            case "}", "]":
                guard !closers.isEmpty else { return nil }
                closers.removeLast()
            default: break
            }
        }
        var closed = partial
        if inString {
            // A cut after a backslash would escape the closing quote.
            if escaped { closed.removeLast() }
            closed.append("\"")
        }
        while let last = closed.last, last.isWhitespace { closed.removeLast() }
        if closed.last == "," { closed.removeLast() }
        if closed.last == ":" { closed.append("null") }
        closed.append(contentsOf: closers.reversed())
        return closed
    }
}
