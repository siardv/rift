import Foundation
import RiftEngine
import SwiftUI

/// render models derived from a DiffReport (sdd §5.3): pure transformation of
/// the engine's provenance ranges into paragraphs, rows, and anchors. built off
/// the main actor alongside the comparison; views only style what's here.
/// all slicing is by utf-8 byte offsets into the ORIGINAL strings — the hunk
/// ranges tile both originals exactly (sdd §10 property), so display is faithful

// MARK: - byte slicing

enum ByteSlice {
    static func clamp(_ range: Range<Int>, count: Int) -> Range<Int> {
        let lo = max(0, min(range.lowerBound, count))
        let hi = max(lo, min(range.upperBound, count))
        return lo..<hi
    }

    static func text(_ bytes: [UInt8], _ range: Range<Int>) -> String {
        let r = clamp(range, count: bytes.count)
        return String(decoding: bytes[r], as: UTF8.self)
    }
}

// MARK: - pieces

enum PieceOp: Sendable, Hashable {
    case equal
    case insert
    case delete
    /// a formatting-only site's bytes; dimmed with a dotted underline when
    /// revealed (fr-10), styled like equal text otherwise
    case formatting
}

struct Piece: Sendable, Hashable, Identifiable {
    let id: Int
    let op: PieceOp
    let text: String
}

// MARK: - prose model (fr-8)

struct ProseParagraph: Sendable, Identifiable {
    let id: Int
    let pieces: [Piece]
}

struct ProseBlock: Sendable, Identifiable {
    let id: Int
    let hunkIndex: Int
    let kind: HunkKind
    /// 1-based change number when kind != .equal
    let ordinal: Int?
    let merged: [ProseParagraph]
    let sideA: [ProseParagraph]
    let sideB: [ProseParagraph]
    let accessibilitySummary: String
}

// MARK: - line model (code/plain)

enum LineRowKind: Sendable, Hashable {
    case context
    case delete
    case insert
}

struct LineRow: Sendable, Identifiable {
    let id: Int
    let hunkIndex: Int
    let isHunkStart: Bool
    let ordinal: Int?
    let kind: LineRowKind
    let numA: Int?
    let numB: Int?
    let pieces: [Piece]
    /// a-side variant for the left half of a synchronized context row
    let altPieces: [Piece]?
    let pairIndex: Int
    let accessibilityLabel: String?
}

struct LinePair: Sendable, Identifiable {
    let id: Int
    let left: LineRow?
    let right: LineRow?
}

// MARK: - navigation + inspector models

struct ChangeAnchor: Sendable, Identifiable {
    /// 1-based ordinal
    let id: Int
    let hunkIndex: Int
}

struct SiteDisplay: Sendable, Identifiable {
    let id: Int
    let level: StrictnessLevel
    let excerptA: String
    let excerptB: String
    let hunkIndex: Int?
}

// MARK: - view model

struct DiffViewModel: Sendable {
    enum Content: Sendable {
        case prose([ProseBlock])
        case lines([LineRow], [LinePair])
    }

    let content: Content
    let changes: [ChangeAnchor]
    let sites: [SiteDisplay]

    static func anchorID(_ hunkIndex: Int) -> String {
        "h\(hunkIndex)"
    }

    // MARK: build

    static func build(report: DiffReport, a: String, b: String) -> DiffViewModel {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        let windowsA = mergeWindows(report.sites.map(\.rangeA).filter { !$0.isEmpty })
        let windowsB = mergeWindows(report.sites.map(\.rangeB).filter { !$0.isEmpty })
        var changes: [ChangeAnchor] = []
        for (index, hunk) in report.document.hunks.enumerated() where hunk.kind != .equal {
            changes.append(ChangeAnchor(id: changes.count + 1, hunkIndex: index))
        }
        let sites = report.sites.enumerated().map { index, site in
            SiteDisplay(id: index,
                        level: site.level,
                        excerptA: visibleExcerpt(aBytes, site.rangeA),
                        excerptB: visibleExcerpt(bBytes, site.rangeB),
                        hunkIndex: hunkIndex(for: site, in: report.document.hunks))
        }
        let content: Content
        if report.profile.profile == .prose {
            content = .prose(buildProse(report: report, aBytes: aBytes, bBytes: bBytes,
                                        windowsA: windowsA, windowsB: windowsB))
        } else {
            let (rows, pairs) = buildLines(report: report, aBytes: aBytes, bBytes: bBytes,
                                           windowsA: windowsA, windowsB: windowsB)
            content = .lines(rows, pairs)
        }
        return DiffViewModel(content: content, changes: changes, sites: sites)
    }

    // MARK: prose blocks

    private static func buildProse(report: DiffReport, aBytes: [UInt8], bBytes: [UInt8],
                                   windowsA: [Range<Int>], windowsB: [Range<Int>]) -> [ProseBlock] {
        var blocks: [ProseBlock] = []
        var nextID = 0
        var ordinal = 0
        for (hunkIndex, hunk) in report.document.hunks.enumerated() {
            let paraA = { (op: PieceOp, windows: [Range<Int>]) -> [ProseParagraph] in
                hunk.unitsA.map { unit in
                    ProseParagraph(id: takeID(&nextID), pieces: cutPieces(
                        bytes: aBytes, range: unit.range, baseOp: op, windows: windows,
                        markOp: .formatting, flattenNewlines: true, nextID: &nextID))
                }
            }
            let paraB = { (op: PieceOp, windows: [Range<Int>]) -> [ProseParagraph] in
                hunk.unitsB.map { unit in
                    ProseParagraph(id: takeID(&nextID), pieces: cutPieces(
                        bytes: bBytes, range: unit.range, baseOp: op, windows: windows,
                        markOp: .formatting, flattenNewlines: true, nextID: &nextID))
                }
            }
            switch hunk.kind {
            case .equal:
                let sideB = paraB(.equal, windowsB)
                let sideA = paraA(.equal, windowsA)
                blocks.append(ProseBlock(
                    id: blocks.count, hunkIndex: hunkIndex, kind: .equal, ordinal: nil,
                    merged: sideB.isEmpty ? sideA : sideB, sideA: sideA, sideB: sideB,
                    accessibilitySummary: "\(max(sideA.count, sideB.count)) unchanged paragraphs"))
            case .insertion:
                ordinal += 1
                let sideB = paraB(.insert, [])
                blocks.append(ProseBlock(
                    id: blocks.count, hunkIndex: hunkIndex, kind: .insertion, ordinal: ordinal,
                    merged: sideB, sideA: [], sideB: sideB,
                    accessibilitySummary: "added: \(plainText(of: sideB))"))
            case .deletion:
                ordinal += 1
                let sideA = paraA(.delete, [])
                blocks.append(ProseBlock(
                    id: blocks.count, hunkIndex: hunkIndex, kind: .deletion, ordinal: ordinal,
                    merged: sideA, sideA: sideA, sideB: [],
                    accessibilitySummary: "removed: \(plainText(of: sideA))"))
            case .modification:
                ordinal += 1
                if hunk.unitsA.count == 1, hunk.unitsB.count == 1, !hunk.segments.isEmpty {
                    let rangeA = hunk.unitsA[0].range
                    let rangeB = hunk.unitsB[0].range
                    let merged = ProseParagraph(id: takeID(&nextID), pieces: mergedPieces(
                        rangeA: rangeA, rangeB: rangeB, segments: hunk.segments,
                        aBytes: aBytes, bBytes: bBytes, nextID: &nextID))
                    let left = ProseParagraph(id: takeID(&nextID), pieces: sidePieces(
                        unitRange: rangeA, segments: hunk.segments, side: .a, bytes: aBytes, nextID: &nextID))
                    let right = ProseParagraph(id: takeID(&nextID), pieces: sidePieces(
                        unitRange: rangeB, segments: hunk.segments, side: .b, bytes: bBytes, nextID: &nextID))
                    let removed = merged.pieces.filter { $0.op == .delete }.map(\.text).joined(separator: " ")
                    let added = merged.pieces.filter { $0.op == .insert }.map(\.text).joined(separator: " ")
                    blocks.append(ProseBlock(
                        id: blocks.count, hunkIndex: hunkIndex, kind: .modification, ordinal: ordinal,
                        merged: [merged], sideA: [left], sideB: [right],
                        accessibilitySummary: "replaced: \(trimForSpeech(removed)), with: \(trimForSpeech(added))"))
                } else {
                    let sideA = paraA(.delete, [])
                    let sideB = paraB(.insert, [])
                    blocks.append(ProseBlock(
                        id: blocks.count, hunkIndex: hunkIndex, kind: .modification, ordinal: ordinal,
                        merged: sideA + sideB, sideA: sideA, sideB: sideB,
                        accessibilitySummary: "replaced: \(plainText(of: sideA)), with: \(plainText(of: sideB))"))
                }
            case .paragraphBoundary:
                ordinal += 1
                let sideA = paraA(.equal, [])
                let sideB = paraB(.equal, [])
                blocks.append(ProseBlock(
                    id: blocks.count, hunkIndex: hunkIndex, kind: .paragraphBoundary, ordinal: ordinal,
                    merged: sideB.isEmpty ? sideA : sideB, sideA: sideA, sideB: sideB,
                    accessibilitySummary: "paragraph split or merge; wording unchanged"))
            }
        }
        return blocks
    }

    /// interleaves segment runs into one flowing paragraph, slicing each run
    /// from its own original so spacing and typography stay faithful (sdd §6.5)
    /// takes byte ranges rather than units: foundation bridges NSUnit as `Unit`,
    /// and the module's facade enum shares the module name, so neither the bare
    /// nor the qualified spelling of the engine type is unambiguous here (m2 erratum)
    private static func mergedPieces(rangeA: Range<Int>, rangeB: Range<Int>, segments: [Segment],
                                     aBytes: [UInt8], bBytes: [UInt8],
                                     nextID: inout Int) -> [Piece] {
        var out: [Piece] = []
        var cursorA = rangeA.lowerBound
        var cursorB = rangeB.lowerBound
        func append(_ op: PieceOp, _ text: String) {
            let flat = text.replacingOccurrences(of: "\n", with: " ")
            guard !flat.isEmpty else { return }
            out.append(Piece(id: takeID(&nextID), op: op, text: flat))
        }
        for segment in segments {
            switch segment.op {
            case .equal:
                var text = segment.text
                if let rb = segment.rangeB, rb.upperBound > cursorB {
                    text = ByteSlice.text(bBytes, cursorB..<rb.upperBound)
                    cursorB = rb.upperBound
                }
                if let ra = segment.rangeA {
                    cursorA = max(cursorA, ra.upperBound)
                }
                append(.equal, text)
            case .insert:
                var text = segment.text
                if let rb = segment.rangeB, rb.upperBound > cursorB {
                    text = ByteSlice.text(bBytes, cursorB..<rb.upperBound)
                    cursorB = rb.upperBound
                }
                append(.insert, text)
            case .delete:
                var text = segment.text
                if let ra = segment.rangeA, ra.upperBound > cursorA {
                    text = ByteSlice.text(aBytes, cursorA..<ra.upperBound)
                    cursorA = ra.upperBound
                }
                append(.delete, text)
            }
        }
        if cursorB < rangeB.upperBound {
            append(.equal, ByteSlice.text(bBytes, cursorB..<rangeB.upperBound))
        }
        return out
    }

    /// one side of a refined pair: equal runs plus that side's own changes
    private static func sidePieces(unitRange: Range<Int>, segments: [Segment], side: PaneID,
                                   bytes: [UInt8], nextID: inout Int) -> [Piece] {
        var out: [Piece] = []
        var cursor = unitRange.lowerBound
        func append(_ op: PieceOp, _ text: String) {
            let flat = text.replacingOccurrences(of: "\n", with: " ")
            guard !flat.isEmpty else { return }
            out.append(Piece(id: takeID(&nextID), op: op, text: flat))
        }
        for segment in segments {
            let range = side == .a ? segment.rangeA : segment.rangeB
            let op: PieceOp
            switch segment.op {
            case .equal: op = .equal
            case .insert:
                guard side == .b else { continue }
                op = .insert
            case .delete:
                guard side == .a else { continue }
                op = .delete
            }
            if let r = range, r.upperBound > cursor {
                append(op, ByteSlice.text(bytes, cursor..<r.upperBound))
                cursor = r.upperBound
            } else if range == nil {
                append(op, segment.text)
            }
        }
        if cursor < unitRange.upperBound {
            append(.equal, ByteSlice.text(bytes, cursor..<unitRange.upperBound))
        }
        return out
    }

    // MARK: line rows

    private static func buildLines(report: DiffReport, aBytes: [UInt8], bBytes: [UInt8],
                                   windowsA: [Range<Int>], windowsB: [Range<Int>])
        -> ([LineRow], [LinePair]) {
        var rows: [LineRow] = []
        var lineA = 1
        var lineB = 1
        var pairIndex = 0
        var ordinal = 0
        var nextID = 0
        for (hunkIndex, hunk) in report.document.hunks.enumerated() {
            var isFirstRowOfHunk = true
            func push(kind: LineRowKind, numA: Int?, numB: Int?, pieces: [Piece],
                      altPieces: [Piece]?, pair: Int, ord: Int?, a11y: String?) {
                rows.append(LineRow(id: rows.count, hunkIndex: hunkIndex,
                                    isHunkStart: isFirstRowOfHunk,
                                    ordinal: isFirstRowOfHunk ? ord : nil,
                                    kind: kind, numA: numA, numB: numB,
                                    pieces: pieces, altPieces: altPieces,
                                    pairIndex: pair, accessibilityLabel: a11y))
                isFirstRowOfHunk = false
            }
            switch hunk.kind {
            case .equal:
                let count = min(hunk.unitsA.count, hunk.unitsB.count)
                for i in 0..<count {
                    let ub = hunk.unitsB[i]
                    let ua = hunk.unitsA[i]
                    let pieces = cutPieces(bytes: bBytes, range: ub.range, baseOp: .equal,
                                           windows: windowsB, markOp: .formatting,
                                           flattenNewlines: false, nextID: &nextID)
                    let alt = cutPieces(bytes: aBytes, range: ua.range, baseOp: .equal,
                                        windows: windowsA, markOp: .formatting,
                                        flattenNewlines: false, nextID: &nextID)
                    push(kind: .context, numA: lineA + i, numB: lineB + i,
                         pieces: pieces, altPieces: alt, pair: pairIndex, ord: nil, a11y: nil)
                    pairIndex += 1
                }
                lineA += hunk.unitsA.count
                lineB += hunk.unitsB.count
            case .deletion:
                ordinal += 1
                for (i, unit) in hunk.unitsA.enumerated() {
                    let text = ByteSlice.text(aBytes, unit.range)
                    push(kind: .delete, numA: lineA + i, numB: nil,
                         pieces: [Piece(id: takeID(&nextID), op: .delete, text: text)],
                         altPieces: nil, pair: pairIndex, ord: ordinal,
                         a11y: "line \(lineA + i) removed: \(trimForSpeech(text))")
                    pairIndex += 1
                }
                lineA += hunk.unitsA.count
            case .insertion:
                ordinal += 1
                for (i, unit) in hunk.unitsB.enumerated() {
                    let text = ByteSlice.text(bBytes, unit.range)
                    push(kind: .insert, numA: nil, numB: lineB + i,
                         pieces: [Piece(id: takeID(&nextID), op: .insert, text: text)],
                         altPieces: nil, pair: pairIndex, ord: ordinal,
                         a11y: "line \(lineB + i) added: \(trimForSpeech(text))")
                    pairIndex += 1
                }
                lineB += hunk.unitsB.count
            case .modification, .paragraphBoundary:
                ordinal += 1
                let refined = hunk.unitsA.count == 1 && hunk.unitsB.count == 1 && !hunk.segments.isEmpty
                let deleteWindows = refined ? mergeWindows(
                    hunk.segments.filter { $0.op == .delete }.compactMap(\.rangeA)) : []
                let insertWindows = refined ? mergeWindows(
                    hunk.segments.filter { $0.op == .insert }.compactMap(\.rangeB)) : []
                let count = max(hunk.unitsA.count, hunk.unitsB.count)
                for i in 0..<count {
                    let pair = pairIndex
                    pairIndex += 1
                    if i < hunk.unitsA.count {
                        let unit = hunk.unitsA[i]
                        let pieces: [Piece]
                        if refined {
                            pieces = cutPieces(bytes: aBytes, range: unit.range, baseOp: .equal,
                                               windows: deleteWindows, markOp: .delete,
                                               flattenNewlines: false, nextID: &nextID)
                        } else {
                            pieces = [Piece(id: takeID(&nextID), op: .delete,
                                            text: ByteSlice.text(aBytes, unit.range))]
                        }
                        push(kind: .delete, numA: lineA + i, numB: nil, pieces: pieces,
                             altPieces: nil, pair: pair, ord: ordinal,
                             a11y: "line \(lineA + i) before: \(trimForSpeech(ByteSlice.text(aBytes, unit.range)))")
                    }
                    if i < hunk.unitsB.count {
                        let unit = hunk.unitsB[i]
                        let pieces: [Piece]
                        if refined {
                            pieces = cutPieces(bytes: bBytes, range: unit.range, baseOp: .equal,
                                               windows: insertWindows, markOp: .insert,
                                               flattenNewlines: false, nextID: &nextID)
                        } else {
                            pieces = [Piece(id: takeID(&nextID), op: .insert,
                                            text: ByteSlice.text(bBytes, unit.range))]
                        }
                        push(kind: .insert, numA: nil, numB: lineB + i, pieces: pieces,
                             altPieces: nil, pair: pair, ord: ordinal,
                             a11y: "line \(lineB + i) after: \(trimForSpeech(ByteSlice.text(bBytes, unit.range)))")
                    }
                }
                lineA += hunk.unitsA.count
                lineB += hunk.unitsB.count
            }
        }
        var pairs: [LinePair] = []
        var i = 0
        while i < rows.count {
            let row = rows[i]
            if i + 1 < rows.count, rows[i + 1].pairIndex == row.pairIndex {
                pairs.append(LinePair(id: pairs.count, left: row, right: rows[i + 1]))
                i += 2
            } else {
                switch row.kind {
                case .context:
                    pairs.append(LinePair(id: pairs.count, left: row, right: row))
                case .delete:
                    pairs.append(LinePair(id: pairs.count, left: row, right: nil))
                case .insert:
                    pairs.append(LinePair(id: pairs.count, left: nil, right: row))
                }
                i += 1
            }
        }
        return (rows, pairs)
    }

    // MARK: shared helpers

    private static func takeID(_ nextID: inout Int) -> Int {
        defer { nextID += 1 }
        return nextID
    }

    /// cuts a byte range into base pieces interrupted by marked windows
    private static func cutPieces(bytes: [UInt8], range: Range<Int>, baseOp: PieceOp,
                                  windows: [Range<Int>], markOp: PieceOp,
                                  flattenNewlines: Bool, nextID: inout Int) -> [Piece] {
        let range = ByteSlice.clamp(range, count: bytes.count)
        var out: [Piece] = []
        func append(_ op: PieceOp, _ r: Range<Int>) {
            guard !r.isEmpty else { return }
            var text = ByteSlice.text(bytes, r)
            if flattenNewlines {
                text = text.replacingOccurrences(of: "\n", with: " ")
            }
            guard !text.isEmpty else { return }
            out.append(Piece(id: takeID(&nextID), op: op, text: text))
        }
        var cursor = range.lowerBound
        for window in windows {
            let w = ByteSlice.clamp(window, count: bytes.count)
                .clamped(to: range)
            guard !w.isEmpty, w.lowerBound >= cursor else { continue }
            if w.lowerBound > cursor {
                append(baseOp, cursor..<w.lowerBound)
            }
            append(markOp, w)
            cursor = w.upperBound
        }
        if cursor < range.upperBound {
            append(baseOp, cursor..<range.upperBound)
        }
        if out.isEmpty {
            append(baseOp, range)
        }
        return out
    }

    private static func mergeWindows(_ ranges: [Range<Int>]) -> [Range<Int>] {
        let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
        var out: [Range<Int>] = []
        for r in sorted {
            if let last = out.last, r.lowerBound <= last.upperBound {
                out[out.count - 1] = last.lowerBound..<max(last.upperBound, r.upperBound)
            } else {
                out.append(r)
            }
        }
        return out
    }

    private static func hunkIndex(for site: FormattingSite, in hunks: [Hunk]) -> Int? {
        if !site.rangeB.isEmpty || site.rangeA.isEmpty {
            let point = site.rangeB.lowerBound
            return hunks.firstIndex { $0.rangeB.contains(point) || $0.rangeB.lowerBound == point }
        }
        let point = site.rangeA.lowerBound
        return hunks.firstIndex { $0.rangeA.contains(point) || $0.rangeA.lowerBound == point }
    }

    /// short excerpt with invisibles made visible, for the inspector list
    private static func visibleExcerpt(_ bytes: [UInt8], _ range: Range<Int>) -> String {
        let raw = ByteSlice.text(bytes, range)
        if raw.isEmpty { return "(nothing)" }
        var out = ""
        for character in raw {
            switch character {
            case " ": out.append("·")
            case "\t": out.append("⇥")
            case "\n": out.append("¶")
            case "\r": out.append("␍")
            case "\u{00A0}": out.append("⍽")
            case "\u{200B}", "\u{FEFF}", "\u{2060}", "\u{00AD}": out.append("◦")
            default: out.append(character)
            }
            if out.count >= 24 {
                out.append("…")
                break
            }
        }
        return out
    }

    private static func plainText(of paragraphs: [ProseParagraph]) -> String {
        trimForSpeech(paragraphs.map { $0.pieces.map(\.text).joined() }.joined(separator: " "))
    }

    private static func trimForSpeech(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if flat.isEmpty { return "(empty)" }
        return flat.count > 120 ? String(flat.prefix(120)) + "…" : flat
    }
}

// MARK: - piece styling (shared by both diff views)

/// turns pieces into an AttributedString per sdd §7.1 / nfr-5: insertions get
/// tint + underline, deletions tint + strikethrough, formatting-only sites the
/// dimmed dotted style when revealed. change runs are wrapped in bidi isolates
/// so rtl segments can't visually reorder (sdd §9)
struct PieceStyler {
    var accessiblePalette: Bool
    var revealFormatting: Bool

    func attributed(_ pieces: [Piece]) -> AttributedString {
        var out = AttributedString()
        for piece in pieces {
            switch piece.op {
            case .equal:
                out += AttributedString(piece.text)
            case .insert:
                var part = AttributedString("\u{2066}" + piece.text + "\u{2069}")
                part.foregroundColor = Theme.insertInk(accessible: accessiblePalette)
                part.backgroundColor = Theme.insertWash(accessible: accessiblePalette)
                part.underlineStyle = .single
                out += part
            case .delete:
                var part = AttributedString("\u{2066}" + piece.text + "\u{2069}")
                part.foregroundColor = Theme.deleteInk(accessible: accessiblePalette)
                part.backgroundColor = Theme.deleteWash(accessible: accessiblePalette)
                part.strikethroughStyle = .single
                out += part
            case .formatting:
                var part = AttributedString(piece.text)
                if revealFormatting {
                    part.foregroundColor = Color.primary.opacity(Theme.formattingOpacity)
                    part.underlineStyle = Text.LineStyle(pattern: .dot)
                }
                out += part
            }
        }
        return out
    }
}
