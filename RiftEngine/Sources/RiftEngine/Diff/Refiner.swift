/// pairing and refinement (sdd §6.5), and the internal hunk representation the
/// classifier and materializer share
enum Refiner {
    /// hunk over unit INDEX ranges; empty ranges are zero-width anchors
    struct RawHunk {
        let kind: HunkKind
        let a: Range<Int>
        let b: Range<Int>
    }

    /// dice similarity over token bigrams; sequences shorter than two tokens fall
    /// back to unigrams (mirrors the corpus reference). grams are byte-keyed and
    /// tagged, so equality is codepoint-exact and a unigram never collides with
    /// a bigram
    static func dice(_ t1: [String], _ t2: [String]) -> Double {
        let g1 = grams(t1)
        let g2 = grams(t2)
        if g1.isEmpty && g2.isEmpty {
            return 1.0
        }
        var counts: [[UInt8]: Int] = [:]
        for g in g1 {
            counts[g, default: 0] += 1
        }
        var intersection = 0
        for g in g2 {
            if let c = counts[g], c > 0 {
                counts[g] = c - 1
                intersection += 1
            }
        }
        return 2.0 * Double(intersection) / Double(g1.count + g2.count)
    }

    private static func grams(_ seq: [String]) -> [[UInt8]] {
        // the 0x00 separator keeps gram boundaries unambiguous
        if seq.count < 2 {
            return seq.map { [0x31, 0x00] + Array($0.utf8) }
        }
        var out: [[UInt8]] = []
        out.reserveCapacity(seq.count - 1)
        for i in 0..<(seq.count - 1) {
            out.append([0x32, 0x00] + Array(seq[i].utf8) + [0x00] + Array(seq[i + 1].utf8))
        }
        return out
    }

    /// groups an op stream into hunks: equal runs pass through; each change block
    /// is paired positionally, a pair with dice >= 0.3 becomes a modification,
    /// anything else pure deletion/insertion; a prose block whose token streams
    /// match exactly is a paragraph split/merge (sdd §3.2, §6.5, §6.6).
    /// returns the hunks plus k, the content-change count (sdd §3.4)
    static func buildRawHunks(ua: [Unit], ub: [Unit], ops: [Aligner.AlignOp],
                              profile: Profile) -> ([RawHunk], Int) {
        var hunks: [RawHunk] = []
        var k = 0
        var idx = 0
        while idx < ops.count {
            if case let .equal(a, b, count) = ops[idx] {
                hunks.append(RawHunk(kind: .equal, a: a..<(a + count), b: b..<(b + count)))
                idx += 1
                continue
            }
            var delStart: Int?
            var delCount = 0
            var insStart: Int?
            var insCount = 0
            gather: while idx < ops.count {
                switch ops[idx] {
                case .equal:
                    break gather
                case let .delete(a, count):
                    if delStart == nil {
                        delStart = a
                        delCount = count
                    } else {
                        delCount += count
                    }
                case let .insert(b, count):
                    if insStart == nil {
                        insStart = b
                        insCount = count
                    } else {
                        insCount += count
                    }
                }
                idx += 1
            }
            var dels: [Int] = []
            if let s = delStart {
                dels = Array(s..<(s + delCount))
            }
            var inss: [Int] = []
            if let s = insStart {
                inss = Array(s..<(s + insCount))
            }
            if profile == .prose, !dels.isEmpty, !inss.isEmpty {
                let ta = dels.flatMap { ua[$0].tokens.map(\.text) }
                let tb = inss.flatMap { ub[$0].tokens.map(\.text) }
                let sameStream = ta.count == tb.count
                    && zip(ta, tb).allSatisfy { Normalizer.utf8Equal($0.0, $0.1) }
                if sameStream, let d0 = dels.first, let dN = dels.last,
                   let i0 = inss.first, let iN = inss.last {
                    hunks.append(RawHunk(kind: .paragraphBoundary,
                                         a: d0..<(dN + 1), b: i0..<(iN + 1)))
                    k += 1
                    continue
                }
            }
            let pairCount = min(dels.count, inss.count)
            for t in 0..<pairCount {
                let ia = dels[t]
                let ib = inss[t]
                let sim = dice(ua[ia].tokens.map(\.text), ub[ib].tokens.map(\.text))
                if sim >= EngineLimits.dicePairingThreshold {
                    hunks.append(RawHunk(kind: .modification, a: ia..<(ia + 1), b: ib..<(ib + 1)))
                    k += 1
                } else {
                    hunks.append(RawHunk(kind: .deletion, a: ia..<(ia + 1), b: ib..<ib))
                    hunks.append(RawHunk(kind: .insertion, a: (ia + 1)..<(ia + 1), b: ib..<(ib + 1)))
                    k += 2
                }
            }
            if dels.count > pairCount, let dLast = dels.last {
                let bAnchor = (inss.last.map { $0 + 1 }) ?? (insStart ?? 0)
                hunks.append(RawHunk(kind: .deletion, a: dels[pairCount]..<(dLast + 1),
                                     b: bAnchor..<bAnchor))
                k += 1
            }
            if inss.count > pairCount, let iLast = inss.last {
                let aAnchor = (dels.last.map { $0 + 1 }) ?? (delStart ?? 0)
                hunks.append(RawHunk(kind: .insertion, a: aAnchor..<aAnchor,
                                     b: inss[pairCount]..<(iLast + 1)))
                k += 1
            }
        }
        return (hunks, k)
    }

    /// word-level segments for a 1:1 modification pair; adjacent single-word
    /// replacements in code additionally refine to character (grapheme) level
    /// when the words are similar enough (sdd §6.5). intra-unit work is capped
    static func segments(unitA: Unit, unitB: Unit, profile: Profile) -> [Segment] {
        if unitA.text.count > EngineLimits.refineCharCap || unitB.text.count > EngineLimits.refineCharCap {
            return []
        }
        let ta = unitA.tokens
        let tb = unitB.tokens
        let ops = Aligner.align(ta.map(\.text), tb.map(\.text))
        var out: [Segment] = []
        var idx = 0
        while idx < ops.count {
            switch ops[idx] {
            case let .equal(a, b, count):
                let sliceA = Array(ta[a..<(a + count)])
                let sliceB = Array(tb[b..<(b + count)])
                out.append(Segment(op: .equal,
                                   text: sliceA.map(\.text).joined(separator: " "),
                                   rangeA: span(sliceA), rangeB: span(sliceB)))
                idx += 1
            case let .delete(a, count):
                // single-word replacement in code: try character-level refinement
                if profile == .code, count == 1, idx + 1 < ops.count,
                   case let .insert(b, insCount) = ops[idx + 1], insCount == 1 {
                    let wa = ta[a]
                    let wb = tb[b]
                    if wa.text.count <= EngineLimits.charPolishCap,
                       wb.text.count <= EngineLimits.charPolishCap,
                       characterDice(wa.text, wb.text) >= EngineLimits.dicePairingThreshold {
                        out.append(contentsOf: characterSegments(wa, wb))
                        idx += 2
                        continue
                    }
                }
                let sliceA = Array(ta[a..<(a + count)])
                out.append(Segment(op: .delete,
                                   text: sliceA.map(\.text).joined(separator: " "),
                                   rangeA: span(sliceA), rangeB: nil))
                idx += 1
            case let .insert(b, count):
                let sliceB = Array(tb[b..<(b + count)])
                out.append(Segment(op: .insert,
                                   text: sliceB.map(\.text).joined(separator: " "),
                                   rangeA: nil, rangeB: span(sliceB)))
                idx += 1
            }
        }
        return out
    }

    private static func span(_ tokens: [Token]) -> Range<Int>? {
        guard let first = tokens.first, let last = tokens.last else { return nil }
        return first.range.lowerBound..<last.range.upperBound
    }

    private static func characterDice(_ a: String, _ b: String) -> Double {
        dice(a.map { String($0) }, b.map { String($0) })
    }

    /// grapheme-cluster diff of one word pair; emoji and combining marks cannot
    /// be split because Character is the unit (sdd §6.5). ranges point at the
    /// enclosing tokens: character provenance stays token-granular (sdd §6.3)
    private static func characterSegments(_ wa: Token, _ wb: Token) -> [Segment] {
        let charsA = Array(wa.text)
        let charsB = Array(wb.text)
        let ops = Aligner.align(charsA.map { String($0) }, charsB.map { String($0) })
        var out: [Segment] = []
        for op in ops {
            switch op {
            case let .equal(a, _, count):
                out.append(Segment(op: .equal,
                                   text: String(charsA[a..<(a + count)]),
                                   rangeA: wa.range, rangeB: wb.range))
            case let .delete(a, count):
                out.append(Segment(op: .delete,
                                   text: String(charsA[a..<(a + count)]),
                                   rangeA: wa.range, rangeB: nil))
            case let .insert(b, count):
                out.append(Segment(op: .insert,
                                   text: String(charsB[b..<(b + count)]),
                                   rangeA: nil, rangeB: wb.range))
            }
        }
        return out
    }
}
