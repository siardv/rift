import CoreTransferable
import Foundation
import RiftEngine
import UniformTypeIdentifiers

/// share/export builders (fr-12, sdd §5.5): renderers over the report — they
/// transform what the engine said, they never re-diff
enum Export {
    // MARK: - plain-text summary

    static func summary(report: DiffReport, a: String, b: String,
                        countsA: TextCounts?, countsB: TextCounts?,
                        modeChoice: ModeChoice) -> String {
        var out = "Rift — comparison summary\n\n"
        out += VerdictText.primary(report.verdict) + "\n"
        if let secondary = VerdictText.secondary(report.verdict) {
            out += secondary.prefix(1).capitalized + secondary.dropFirst() + "\n"
        }
        out += "\n"
        let p = report.profile
        let auto = p.isAutomatic ? "auto-detected" : "override"
        out += "Profile: \(p.profile.rawValue.capitalized) (\(auto)) — \(p.explanation)\n"
        if p.isIndentationSensitive {
            out += "Indentation looks meaning-bearing, so it stays significant.\n"
        }
        out += "Mode: \(modeChoice.label)\n\nLadder:\n"
        for row in report.ladder {
            var line = "  \(row.level.label) \(row.level.displayName.lowercased()) — "
            line += row.isEqual ? "equal at this level" : "still different"
            if row.resolvedSiteCount > 0 {
                line += " · resolves \(row.resolvedSiteCount)"
            }
            out += line + "\n"
        }
        if let ca = countsA, let cb = countsB {
            out += "\nA: \(counts(ca))\nB: \(counts(cb))\n"
        }
        let changes = changeExcerpts(document: report.document, a: a, b: b)
        if !changes.isEmpty {
            out += "\nContent changes:\n" + changes.joined(separator: "\n") + "\n"
        }
        return out
    }

    private static func counts(_ c: TextCounts) -> String {
        "\(c.characters.formatted()) characters · \(c.words.formatted()) words · \(c.lines.formatted()) lines"
    }

    private static func changeExcerpts(document: DiffDocument, a: String, b: String) -> [String] {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        var out: [String] = []
        var ordinal = 0
        for hunk in document.hunks where hunk.kind != .equal {
            ordinal += 1
            if out.count >= 50 {
                out.append("  … more changes not listed")
                break
            }
            let left = excerpt(bytes: aBytes, range: hunk.rangeA)
            let right = excerpt(bytes: bBytes, range: hunk.rangeB)
            switch hunk.kind {
            case .insertion:
                out.append("  \(ordinal). added: \(right)")
            case .deletion:
                out.append("  \(ordinal). removed: \(left)")
            case .paragraphBoundary:
                out.append("  \(ordinal). paragraph split/merge: \(right)")
            default:
                out.append("  \(ordinal). \(left) → \(right)")
            }
        }
        return out
    }

    private static func excerpt(bytes: [UInt8], range: Range<Int>) -> String {
        let lo = max(0, min(range.lowerBound, bytes.count))
        let hi = max(lo, min(range.upperBound, bytes.count))
        let raw = String(decoding: bytes[lo..<hi], as: UTF8.self)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if raw.isEmpty { return "(empty)" }
        return raw.count > 60 ? String(raw.prefix(60)) + "…" : raw
    }

    // MARK: - unified .patch (fr-12)

    private enum PatchEntry {
        case context(String)
        case delete(String)
        case insert(String)

        var consumesA: Bool {
            if case .insert = self { return false }
            return true
        }

        var consumesB: Bool {
            if case .delete = self { return false }
            return true
        }

        var rendered: String {
            switch self {
            case .context(let t): return " " + t
            case .delete(let t): return "-" + t
            case .insert(let t): return "+" + t
            }
        }
    }

    /// builds a valid unified diff from the hunk tiling (hunk byte ranges tile
    /// both originals exactly, so line reconstruction is total). content-equal
    /// hunks whose raw bytes still differ (formatting-only) are emitted as
    /// -/+ pairs, keeping the patch honestly applicable
    static func unifiedPatch(a: String, b: String, document: DiffDocument) -> String {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        var flat: [PatchEntry] = []
        for hunk in document.hunks {
            let lo = max(0, min(hunk.rangeA.lowerBound, aBytes.count))
            let hi = max(lo, min(hunk.rangeA.upperBound, aBytes.count))
            let blo = max(0, min(hunk.rangeB.lowerBound, bBytes.count))
            let bhi = max(blo, min(hunk.rangeB.upperBound, bBytes.count))
            let sliceA = aBytes[lo..<hi]
            let sliceB = bBytes[blo..<bhi]
            // byte-exact equality test; String == would blur nfc (m1 erratum)
            if hunk.kind == .equal, sliceA.elementsEqual(sliceB) {
                for line in splitLines(String(decoding: sliceA, as: UTF8.self)) {
                    flat.append(.context(line))
                }
            } else {
                for line in splitLines(String(decoding: sliceA, as: UTF8.self)) {
                    flat.append(.delete(line))
                }
                for line in splitLines(String(decoding: sliceB, as: UTF8.self)) {
                    flat.append(.insert(line))
                }
            }
        }
        let changeIndices = flat.indices.filter {
            if case .context = flat[$0] { return false }
            return true
        }
        guard !changeIndices.isEmpty else {
            return "--- a\n+++ b\n"
        }
        // merge ±3-line context windows around change runs
        var windows: [(Int, Int)] = []
        for i in changeIndices {
            let lo = max(0, i - 3)
            let hi = min(flat.count - 1, i + 3)
            if let last = windows.last, lo <= last.1 + 1 {
                windows[windows.count - 1].1 = max(last.1, hi)
            } else {
                windows.append((lo, hi))
            }
        }
        var aBefore = [Int](repeating: 0, count: flat.count + 1)
        var bBefore = [Int](repeating: 0, count: flat.count + 1)
        for (i, entry) in flat.enumerated() {
            aBefore[i + 1] = aBefore[i] + (entry.consumesA ? 1 : 0)
            bBefore[i + 1] = bBefore[i] + (entry.consumesB ? 1 : 0)
        }
        let lastAIndex = flat.lastIndex(where: \.consumesA)
        let lastBIndex = flat.lastIndex(where: \.consumesB)
        let aNoEOF = !a.isEmpty && !a.hasSuffix("\n")
        let bNoEOF = !b.isEmpty && !b.hasSuffix("\n")
        var out = "--- a\n+++ b\n"
        for (lo, hi) in windows {
            let aCount = aBefore[hi + 1] - aBefore[lo]
            let bCount = bBefore[hi + 1] - bBefore[lo]
            let aStart = aCount == 0 ? aBefore[lo] : aBefore[lo] + 1
            let bStart = bCount == 0 ? bBefore[lo] : bBefore[lo] + 1
            out += "@@ -\(aStart),\(aCount) +\(bStart),\(bCount) @@\n"
            for i in lo...hi {
                out += flat[i].rendered + "\n"
                if i == lastAIndex, aNoEOF, flat[i].consumesA {
                    out += "\\ No newline at end of file\n"
                } else if i == lastBIndex, bNoEOF, flat[i].consumesB {
                    out += "\\ No newline at end of file\n"
                }
            }
        }
        return out
    }

    private static func splitLines(_ s: String) -> [String] {
        guard !s.isEmpty else { return [] }
        var lines = s.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if s.hasSuffix("\n") {
            lines.removeLast()
        }
        return lines
    }
}

/// lazily materialized .patch payload for the share sheet (fr-12); the data
/// closure runs only when the user actually exports
struct PatchExport: Transferable, Sendable {
    let a: String
    let b: String
    let document: DiffDocument

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { item in
            Data(Export.unifiedPatch(a: item.a, b: item.b, document: item.document).utf8)
        }
        .suggestedFileName("rift-comparison.patch")
    }
}
