//
//  AgentReplyMarkdown.swift
//  Tenra
//
//  The assistant's text blocks are Markdown (the server's prompt asks for a bold key point,
//  "- " bullets, "1. " steps and an occasional "### " heading), shown with DesignKit's
//  `ArticleBody`, which draws the blocks and the inline **bold**, *italic* and links. Splitting
//  the Markdown into its blocks is the app's part (ArticleBody's contract). Anything else stays a
//  paragraph, so an answer written without Markdown reads as before.
//

import Foundation

nonisolated enum AgentReplyMarkdown {
    static func blocks(_ text: String) -> [ArticleBody.Block] {
        var blocks: [ArticleBody.Block] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var steps: [String] = []
        var note: [String] = []

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            if !bullets.isEmpty { blocks.append(.bullets(bullets)) }
            if !steps.isEmpty { blocks.append(.steps(steps)) }
            if !note.isEmpty { blocks.append(.note(note.joined(separator: "\n"))) }
            paragraph = []
            bullets = []
            steps = []
            note = []
        }

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
            } else if let heading = heading(line) {
                flush()
                blocks.append(heading)
            } else if let item = bullet(line) {
                if bullets.isEmpty { flush() }
                bullets.append(item)
            } else if let item = step(line) {
                if steps.isEmpty { flush() }
                steps.append(item)
            } else if line.hasPrefix(">") {
                if note.isEmpty { flush() }
                note.append(line.dropFirst().trimmingCharacters(in: .whitespaces))
            } else {
                if paragraph.isEmpty { flush() }
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }

    /// "# …" and "## …" are sections, "### …" and deeper subsections.
    private static func heading(_ line: String) -> ArticleBody.Block? {
        let marks = line.prefix { $0 == "#" }.count
        guard marks > 0, marks <= 6 else { return nil }
        let rest = line.dropFirst(marks)
        guard rest.first == " " else { return nil }
        let title = rest.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return .heading(title, level: marks <= 2 ? 2 : 3)
    }

    /// "- item", "* item", "• item"; "**bold**" at the start of a line is not a bullet.
    private static func bullet(_ line: String) -> String? {
        for mark in ["- ", "* ", "• "] where line.hasPrefix(mark) {
            let item = line.dropFirst(mark.count).trimmingCharacters(in: .whitespaces)
            return item.isEmpty ? nil : item
        }
        return nil
    }

    /// "1. item" or "1) item".
    private static func step(_ line: String) -> String? {
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard let mark = rest.first, mark == "." || mark == ")", rest.dropFirst().first == " " else { return nil }
        let item = rest.dropFirst(2).trimmingCharacters(in: .whitespaces)
        return item.isEmpty ? nil : item
    }
}
