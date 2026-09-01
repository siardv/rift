/// unit-level alignment (sdd §6.4): common prefix/suffix trim, then a minimal
/// edit script via the standard library's myers-based CollectionDifference,
/// re-expressed as coalesced runs in document order (deletes before inserts).
/// units are keyed by their utf-8 bytes so equality is codepoint-exact —
/// swift's String ==/hashing use canonical equivalence, which must not leak
/// into alignment (an nfc-only difference is l1's business, sdd §3.2)
enum Aligner {
    enum AlignOp: Equatable {
        case equal(a: Int, b: Int, count: Int)
        case delete(a: Int, count: Int)
        case insert(b: Int, count: Int)
    }

    static func align(_ textsA: [String], _ textsB: [String]) -> [AlignOp] {
        let keysA = textsA.map { Array($0.utf8) }
        let keysB = textsB.map { Array($0.utf8) }
        let nA = keysA.count
        let nB = keysB.count
        var p = 0
        while p < nA && p < nB && keysA[p] == keysB[p] {
            p += 1
        }
        var q = 0
        while q < nA - p && q < nB - p && keysA[nA - 1 - q] == keysB[nB - 1 - q] {
            q += 1
        }
        let midA = Array(keysA[p..<(nA - q)])
        let midB = Array(keysB[p..<(nB - q)])
        var ops: [AlignOp] = []
        if p > 0 {
            ops.append(.equal(a: 0, b: 0, count: p))
        }
        ops.append(contentsOf: middleOps(midA, midB, offsetA: p, offsetB: p))
        if q > 0 {
            ops.append(.equal(a: nA - q, b: nB - q, count: q))
        }
        return coalesce(ops)
    }

    private static func middleOps(_ midA: [[UInt8]], _ midB: [[UInt8]],
                                  offsetA: Int, offsetB: Int) -> [AlignOp] {
        if midA.isEmpty && midB.isEmpty {
            return []
        }
        if midA.isEmpty {
            return [.insert(b: offsetB, count: midB.count)]
        }
        if midB.isEmpty {
            return [.delete(a: offsetA, count: midA.count)]
        }
        let diff = midB.difference(from: midA)
        var removed = Set<Int>()
        for change in diff.removals {
            if case let .remove(offset, _, _) = change {
                removed.insert(offset)
            }
        }
        var inserted = Set<Int>()
        for change in diff.insertions {
            if case let .insert(offset, _, _) = change {
                inserted.insert(offset)
            }
        }
        var ops: [AlignOp] = []
        var ia = 0
        var ib = 0
        while ia < midA.count || ib < midB.count {
            if ia < midA.count && removed.contains(ia) {
                ops.append(.delete(a: offsetA + ia, count: 1))
                ia += 1
            } else if ib < midB.count && inserted.contains(ib) {
                ops.append(.insert(b: offsetB + ib, count: 1))
                ib += 1
            } else if ia < midA.count && ib < midB.count {
                ops.append(.equal(a: offsetA + ia, b: offsetB + ib, count: 1))
                ia += 1
                ib += 1
            } else if ia < midA.count {
                ops.append(.delete(a: offsetA + ia, count: 1))
                ia += 1
            } else {
                ops.append(.insert(b: offsetB + ib, count: 1))
                ib += 1
            }
        }
        return ops
    }

    static func coalesce(_ ops: [AlignOp]) -> [AlignOp] {
        var out: [AlignOp] = []
        for op in ops {
            if let last = out.last {
                switch (last, op) {
                case let (.equal(a, b, c1), .equal(a2, b2, c2)) where a + c1 == a2 && b + c1 == b2:
                    out[out.count - 1] = .equal(a: a, b: b, count: c1 + c2)
                    continue
                case let (.delete(a, c1), .delete(a2, c2)) where a + c1 == a2:
                    out[out.count - 1] = .delete(a: a, count: c1 + c2)
                    continue
                case let (.insert(b, c1), .insert(b2, c2)) where b + c1 == b2:
                    out[out.count - 1] = .insert(b: b, count: c1 + c2)
                    continue
                default:
                    break
                }
            }
            out.append(op)
        }
        return out
    }

    /// coarse alignment for pathological inputs (sdd §6.4): only the common
    /// prefix and suffix are matched; the middle stays one block
    static func prefixSuffixOnly(_ textsA: [String], _ textsB: [String]) -> [AlignOp] {
        let keysA = textsA.map { Array($0.utf8) }
        let keysB = textsB.map { Array($0.utf8) }
        let nA = keysA.count
        let nB = keysB.count
        var p = 0
        while p < nA && p < nB && keysA[p] == keysB[p] {
            p += 1
        }
        var q = 0
        while q < nA - p && q < nB - p && keysA[nA - 1 - q] == keysB[nB - 1 - q] {
            q += 1
        }
        var ops: [AlignOp] = []
        if p > 0 {
            ops.append(.equal(a: 0, b: 0, count: p))
        }
        if nA - p - q > 0 {
            ops.append(.delete(a: p, count: nA - p - q))
        }
        if nB - p - q > 0 {
            ops.append(.insert(b: p, count: nB - p - q))
        }
        if q > 0 {
            ops.append(.equal(a: nA - q, b: nB - q, count: q))
        }
        return ops
    }

    /// multiset overlap ratio used by the pathology guard (sdd §6.4)
    static func commonUnitRatio(_ textsA: [String], _ textsB: [String]) -> Double {
        if textsA.isEmpty && textsB.isEmpty {
            return 1.0
        }
        var counts: [[UInt8]: Int] = [:]
        for t in textsA {
            counts[Array(t.utf8), default: 0] += 1
        }
        var common = 0
        for t in textsB {
            let key = Array(t.utf8)
            if let c = counts[key], c > 0 {
                counts[key] = c - 1
                common += 1
            }
        }
        return Double(common) / Double(max(textsA.count, textsB.count))
    }
}
