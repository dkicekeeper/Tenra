//
//  StatementTableAssembler.swift
//  Tenra
//
//  Rebuilds a statement's transaction table from positioned words, anchored on the
//  table's header row ("Дата | Сумма | Операция | Детали"). PDFTextLayerExtractor's
//  gap-split rows cannot represent two things real statements do:
//
//  1. Cells that wrap onto several lines. Kaspi top-aligns them ("Перевод на свой" /
//     "счет"); Freedom centers them vertically, so half of a 10-line transfer detail
//     sits ABOVE the date line and "Сумма в обработке" is split around it.
//  2. Cells that do not start where the header does. Freedom centers the "Детали"
//     header over a column whose text starts 70pt further left, and an empty cell
//     shifts every later gap-split cell one column to the left.
//
//  So: every record is one date line (the anchor) plus the wrapped lines around it,
//  and every word lands in the header column whose whitespace river it falls between.
//  Lines above the header (account summary, "Доступно на ...") and footers never
//  become rows. Before this, a Kaspi import lost every merchant name and turned the
//  summary block into three fake income rows.
//
//  Pure geometry, no PDFKit (import.md rule 1), so tests build words by hand.
//

import Foundation

nonisolated enum StatementTableAssembler {

    struct Word: Sendable, Equatable {
        let text: String
        let minX: Double
        let maxX: Double
        /// PDF space: y grows upward, so the top of the page has the largest y.
        let minY: Double
        let maxY: Double

        var midX: Double { (minX + maxX) / 2 }
        var midY: Double { (minY + maxY) / 2 }
    }

    /// One visual row, words left to right. Pages list lines top to bottom.
    typealias Line = [Word]

    /// One table per header segment, per page. Nil when the document has no
    /// transaction-table header or no dated row under it; the caller then keeps its
    /// gap-split tables.
    static func assemble(pages: [[Line]]) -> [[DocumentSnapshot.Table]]? {
        var layout: Layout?
        var result: [[DocumentSnapshot.Table]] = []
        var producedRows = false

        for lines in pages {
            let splitThreshold = cellSplitThreshold(lines)
            var tables: [DocumentSnapshot.Table] = []
            var segmentStart = 0
            var headerMidY: Double?

            func flush(upTo end: Int) {
                guard var current = layout, segmentStart < end else { return }
                let rows = assembleSegment(Array(lines[segmentStart..<end]),
                                           headerMidY: headerMidY,
                                           layout: &current)
                layout = current
                if !rows.isEmpty {
                    producedRows = true
                    tables.append(DocumentSnapshot.Table(rows: [current.titles] + rows))
                }
            }

            for (index, line) in lines.enumerated() {
                guard var header = headerLayout(line, splitThreshold: splitThreshold) else { continue }
                flush(upTo: index)
                // A header repeated on the next page continues the same table.
                if let previous = layout, previous.titles == header.titles {
                    header.wrapsAboveAnchor = previous.wrapsAboveAnchor
                    header.wrapPitch = previous.wrapPitch
                    header.carriedLines = previous.carriedLines
                }
                layout = header
                headerMidY = midY(line)
                segmentStart = index + 1
            }
            flush(upTo: lines.count)
            result.append(tables)
        }

        return producedRows ? result : nil
    }

    // MARK: - Header

    private struct Column {
        let title: String
        let minX: Double
        let maxX: Double
        var center: Double { (minX + maxX) / 2 }
    }

    private struct Layout {
        let columns: [Column]
        let dateColumn: Int
        /// Set once a record is seen owning a line above its date line (centered
        /// cells). Header-less continuation pages only look above their first
        /// anchor when this is true, so a page-top preamble never joins a row of a
        /// top-aligned statement.
        var wrapsAboveAnchor = false
        /// Widest step between two lines of one wrapped record seen so far.
        var wrapPitch: Double?
        /// Lines a page ended with that belong to the next page's first record.
        var carriedLines: [Line] = []

        var titles: [String] { columns.map(\.title) }
    }

    private static func headerLayout(_ line: Line, splitThreshold: Double) -> Layout? {
        let cells = split(line, threshold: splitThreshold)
        guard let dateColumn = ColumnRoleResolver.transactionHeaderDateIndex(in: cells.map(\.title)) else {
            return nil
        }
        return Layout(columns: cells, dateColumn: dateColumn)
    }

    /// Gap-split cells of one line, the same rule the extractor uses: a gap several
    /// times wider than the page's median word gap starts a new cell.
    private static func split(_ line: Line, threshold: Double) -> [Column] {
        var columns: [Column] = []
        var current: [Word] = []
        func close() {
            guard let first = current.first, let last = current.last else { return }
            columns.append(Column(title: current.map(\.text).joined(separator: " "),
                                  minX: first.minX, maxX: last.maxX))
            current = []
        }
        for word in line {
            if let previous = current.last, word.minX - previous.maxX > threshold { close() }
            current.append(word)
        }
        close()
        return columns
    }

    private static func cellSplitThreshold(_ lines: [Line]) -> Double {
        let gaps = lines.flatMap { line in
            zip(line, line.dropFirst()).map { $1.minX - $0.maxX }
        }.sorted()
        guard !gaps.isEmpty else { return 6 }
        return max(gaps[gaps.count / 2] * 3, 6)
    }

    // MARK: - Records

    private static func assembleSegment(_ lines: [Line], headerMidY: Double?, layout: inout Layout) -> [[String]] {
        let anchors = lines.indices.filter { isAnchor(lines[$0], layout: layout) }
        guard let firstAnchor = anchors.first, let lastAnchor = anchors.last else { return [] }

        let mids = lines.map(midY)
        let carried = layout.carriedLines
        layout.carriedLines = []
        var owner = [Int?](repeating: nil, count: lines.count)
        for anchor in anchors { owner[anchor] = anchor }

        // Between two anchors: split the wrapped lines at the widest vertical gap
        // (the padding between records). When no gap stands out, the cells are
        // top-aligned and every wrapped line continues the record above.
        for (upper, lower) in zip(anchors, anchors.dropFirst()) where lower - upper > 1 {
            let positions = [mids[upper]] + (upper + 1..<lower).map { mids[$0] } + [mids[lower]]
            let splitAt = decisiveSplit(positions) ?? positions.count - 2
            for (offset, line) in (upper + 1..<lower).enumerated() {
                owner[line] = offset < splitAt ? upper : lower
            }
            if splitAt < lower - upper - 1 { layout.wrapsAboveAnchor = true }
        }

        // Line pitch inside a wrapped cell, as seen between date lines. An edge line
        // further than a quarter pitch beyond it is not a wrap: it is a record broken
        // by the page end, a footnote, or a page header.
        let wrapSteps = anchors.flatMap { anchor -> [Double] in
            let members = lines.indices.filter { owner[$0] == anchor }
            return zip(members, members.dropFirst()).map { mids[$0] - mids[$1] }
        }
        if let widest = wrapSteps.max() { layout.wrapPitch = max(layout.wrapPitch ?? 0, widest) }
        let chainLimit = layout.wrapPitch.map { $0 * 1.25 }
            ?? chainLimit(lines: Array(lines[firstAnchor...lastAnchor]))

        // Columns come from the table's core (date lines and the lines between
        // them); the edges above the first and below the last date line are where
        // preambles and footnotes sit, and they must not bend the rivers.
        let coreLines = lines.indices.filter { owner[$0] != nil }.map { lines[$0] }
        let boundaries = columnBoundaries(layout.columns, lines: coreLines)

        // Edge lines, nearest first. A line that is close enough still stops the
        // chain when a word straddles a column river: wrapped cell text stays inside
        // its column, while a footnote ("- Сумма заблокирована. Банк ожидает ...")
        // or page header runs across the whole table.
        func attach(_ candidates: [Int], to anchor: Int) {
            for line in candidates {
                guard !straddles(lines[line], boundaries: boundaries) else { break }
                owner[line] = anchor
                if line < anchor { layout.wrapsAboveAnchor = true }
            }
        }

        // Above the first anchor: under a header, the same split against the header
        // line; on a continuation page, only a chain of close lines and only for
        // centered layouts.
        if firstAnchor > 0 {
            let above = Array(0..<firstAnchor)
            if let headerMidY {
                let positions = [headerMidY] + above.map { mids[$0] } + [mids[firstAnchor]]
                if let splitAt = decisiveSplit(positions) {
                    attach(above.enumerated().filter { $0.offset >= splitAt }.map(\.element).reversed(),
                           to: firstAnchor)
                }
            } else if layout.wrapsAboveAnchor {
                attach(chain(from: firstAnchor, through: above.reversed(), mids: mids, limit: chainLimit),
                       to: firstAnchor)
            }
        }

        // Below the last anchor: a chain of close lines, then the footer.
        attach(chain(from: lastAnchor, through: Array((lastAnchor + 1)..<lines.count), mids: mids, limit: chainLimit),
               to: lastAnchor)

        // A centered record broken by the page end leaves its first wrapped lines
        // under the last date line, too far down to be a wrap of it. They continue
        // on the next page, so they go to that page's first record.
        if layout.wrapsAboveAnchor {
            let lastOwned = lines.indices.last { owner[$0] != nil } ?? lastAnchor
            let tail = chain(from: lastOwned, through: Array((lastOwned + 1)..<lines.count),
                             mids: mids, limit: chainLimit * 2)
            layout.carriedLines = tail.prefix { !straddles(lines[$0], boundaries: boundaries) }.map { lines[$0] }
        }

        let numeric = numericColumns(anchors.map { lines[$0] }, boundaries: boundaries,
                                     columnCount: layout.columns.count)

        let level = glyphHeight(lines) * 0.6
        return anchors.map { anchor in
            var cells = [[String]](repeating: [], count: layout.columns.count)
            if anchor == firstAnchor {
                for word in carried.joined() {
                    let column = column(of: word, boundaries: boundaries)
                    if !numeric.contains(column) { cells[column].append(word.text) }
                }
            }
            for index in lines.indices where owner[index] == anchor {
                for word in lines[index] {
                    let column = column(of: word, boundaries: boundaries)
                    // Amounts and dates come from the date line only: a stray wrapped
                    // line must never turn "- 995,00 ₸" into a different number. A line
                    // level with it counts too (a record broken by a page end paints its
                    // amount 2pt off the date and gets a visual line of its own).
                    if numeric.contains(column), abs(mids[index] - mids[anchor]) > level { continue }
                    cells[column].append(word.text)
                }
            }
            return cells.map { $0.joined(separator: " ") }
        }
    }

    /// Lines reachable from `anchor` in steps no longer than `limit`, nearest first.
    private static func chain(from anchor: Int, through candidates: [Int], mids: [Double], limit: Double) -> [Int] {
        var previous = mids[anchor]
        var result: [Int] = []
        for line in candidates {
            guard abs(previous - mids[line]) <= limit else { break }
            result.append(line)
            previous = mids[line]
        }
        return result
    }

    private static func straddles(_ line: Line, boundaries: [Double]) -> Bool {
        line.contains { word in
            boundaries.contains { word.minX < $0 - 1 && word.maxX > $0 + 1 }
        }
    }

    /// A date line has a date word as the first word under the date header.
    /// Continuation text that merely contains a date ("20.09.2026. Вкладчик: ...")
    /// sits in another column; a summary line ("Доступно на 24.09.26:") starts
    /// with a word.
    private static func isAnchor(_ line: Line, layout: Layout) -> Bool {
        let header = layout.columns[layout.dateColumn]
        let slack = 12.0
        guard let first = line.first(where: { $0.maxX > header.minX - slack && $0.minX < header.maxX + slack })
        else { return false }
        return !first.text.contains(where: \.isLetter) && DateTokenParser.looksLikeDate(first.text)
    }

    /// Index of the gap (in `positions`, top to bottom) after which lines belong to
    /// the lower record, when that gap is clearly the widest. Nil when gaps are
    /// uniform, which is what top-aligned rows with a steady line pitch look like.
    private static func decisiveSplit(_ positions: [Double]) -> Int? {
        let gaps = zip(positions, positions.dropFirst()).map { $0 - $1 }
        guard gaps.count >= 2,
              let widest = gaps.indices.max(by: { gaps[$0] < gaps[$1] }) else { return nil }
        let runnerUp = gaps.enumerated().filter { $0.offset != widest }.map(\.element).max() ?? 0
        return gaps[widest] >= runnerUp * 1.25 ? widest : nil
    }

    /// How far a wrapped line may sit from the line before it and still belong to
    /// the same record, before any wrapped record has been seen: 1.5 line pitches,
    /// and never less than two glyph heights.
    private static func chainLimit(lines: [Line]) -> Double {
        let height = glyphHeight(lines)
        let mids = lines.map(midY)
        let pitches = zip(mids, mids.dropFirst()).map { $0 - $1 }.sorted()
        let pitch = pitches.isEmpty ? height * 1.8 : pitches[pitches.count / 2]
        return max(pitch * 1.5, height * 2)
    }

    private static func glyphHeight(_ lines: [Line]) -> Double {
        let heights = lines.flatMap { $0.map { $0.maxY - $0.minY } }.sorted()
        return heights.isEmpty ? 10 : heights[heights.count / 2]
    }

    private static func midY(_ line: Line) -> Double {
        let low = line.map(\.minY).min() ?? 0
        let high = line.map(\.maxY).max() ?? 0
        return (low + high) / 2
    }

    // MARK: - Columns

    /// The x between two neighbouring header centers that the fewest record lines
    /// cover, taking the middle of the longest such run: the whitespace river
    /// between the columns, wherever the header text itself sits.
    private static func columnBoundaries(_ columns: [Column], lines: [Line]) -> [Double] {
        zip(columns, columns.dropFirst()).map { left, right in
            let low = left.center, high = right.center
            guard high - low > 1 else { return (low + high) / 2 }
            let words = lines.map { line in line.filter { $0.maxX >= low && $0.minX <= high } }
            let step = 0.5
            var best: (coverage: Int, start: Double, length: Double) = (.max, low, 0)
            var runStart = low
            var runCoverage = -1
            var x = low
            while x <= high {
                let coverage = words.filter { line in line.contains { $0.minX <= x && x <= $0.maxX } }.count
                if coverage != runCoverage {
                    runStart = x
                    runCoverage = coverage
                }
                let length = x - runStart
                if coverage < best.coverage || (coverage == best.coverage && length > best.length) {
                    best = (coverage, runStart, length)
                }
                x += step
            }
            return best.start + best.length / 2
        }
    }

    private static func column(of word: Word, boundaries: [Double]) -> Int {
        boundaries.firstIndex { word.midX < $0 } ?? boundaries.count
    }

    /// An amount or a date, optionally with a currency code ("- 995,00 ₸", "49.06 USD").
    /// `looksLikeMoney` alone is not enough: it accepts any text with a digit, and
    /// transfer details full of reference numbers ("Референс: FBK20260913-") would
    /// turn the details column numeric and drop every wrapped line of it.
    private static func isNumericCell(_ text: String) -> Bool {
        text.filter(\.isLetter).count <= 3
            && (DateTokenParser.looksLikeDate(text) || MoneyTokenParser.looksLikeMoney(text))
    }

    /// Columns whose date-line cells are mostly amounts or dates.
    private static func numericColumns(_ anchorLines: [Line], boundaries: [Double], columnCount: Int) -> Set<Int> {
        var filled = [Int](repeating: 0, count: columnCount)
        var numeric = [Int](repeating: 0, count: columnCount)
        for line in anchorLines {
            var cells = [[String]](repeating: [], count: columnCount)
            for word in line { cells[column(of: word, boundaries: boundaries)].append(word.text) }
            for (index, words) in cells.enumerated() where !words.isEmpty {
                filled[index] += 1
                if isNumericCell(words.joined(separator: " ")) { numeric[index] += 1 }
            }
        }
        return Set((0..<columnCount).filter { filled[$0] > 0 && numeric[$0] * 10 >= filled[$0] * 6 })
    }
}
