/// formatting accounting (sdd §3.4, §6.6): wherever raw slices differ inside
/// content-equal regions, one site is recorded and attributed to the lowest
/// ladder level whose canonicalization resolves it. modification pairs anchor
/// gap accounting but are never sites themselves; gaps count only where both
/// sides have well-defined boundaries.
/// all equality here is byte-exact: swift's String == uses canonical
/// equivalence, which would silently swallow nfc-only differences (an l1 rule)
enum FormattingAccountant {
    struct AlignedPair {
        let a: Int
        let b: Int
        let isContent: Bool
    }

    static func pairs(from hunks: [Refiner.RawHunk]) -> [AlignedPair] {
        var out: [AlignedPair] = []
        for h in hunks {
            switch h.kind {
            case .equal:
                for t in 0..<h.a.count {
                    out.append(AlignedPair(a: h.a.lowerBound + t, b: h.b.lowerBound + t, isContent: false))
                }
            case .modification:
                if h.a.count == 1 && h.b.count == 1 {
                    out.append(AlignedPair(a: h.a.lowerBound, b: h.b.lowerBound, isContent: true))
                }
            default:
                break
            }
        }
        return out.sorted { $0.a < $1.a }
    }

    static func lowestEqualLevel(_ sa: String, _ sb: String, profile: Profile,
                                 rules: RuleSet, sensitive: Bool) -> Int? {
        for level in 1...3 {
            let ca = Normalizer.canonicalString(sa, level: level, profile: profile,
                                                rules: rules, sensitive: sensitive)
            let cb = Normalizer.canonicalString(sb, level: level, profile: profile,
                                                rules: rules, sensitive: sensitive)
            if Normalizer.utf8Equal(ca, cb) {
                return level
            }
        }
        return nil
    }

    static func sliceString(_ bytes: [UInt8], _ range: Range<Int>) -> String {
        String(decoding: bytes[range], as: UTF8.self)
    }

    /// returns the attributed level (1...3) of every site, in document order
    static func siteLevels(aBytes: [UInt8], bBytes: [UInt8], ua: [Unit], ub: [Unit],
                           pairs: [AlignedPair], profile: Profile,
                           rules: RuleSet, sensitive: Bool) -> [Int] {
        var out: [Int] = []
        func record(_ ra: Range<Int>, _ rb: Range<Int>) {
            // byte-exact difference test on the raw slices
            if aBytes[ra] != bBytes[rb] {
                let sa = sliceString(aBytes, ra)
                let sb = sliceString(bBytes, rb)
                out.append(lowestEqualLevel(sa, sb, profile: profile,
                                            rules: rules, sensitive: sensitive) ?? 3)
            }
        }
        for pair in pairs where !pair.isContent {
            record(ua[pair.a].range, ub[pair.b].range)
        }
        if pairs.isEmpty {
            // no aligned units at all: the whole documents form one gap; count it
            // only when some level resolves it (otherwise the difference is content)
            if aBytes != bBytes {
                let sa = String(decoding: aBytes, as: UTF8.self)
                let sb = String(decoding: bBytes, as: UTF8.self)
                if let level = lowestEqualLevel(sa, sb, profile: profile,
                                                rules: rules, sensitive: sensitive) {
                    out.append(level)
                }
            }
            return out
        }
        if let first = pairs.first, first.a == 0, first.b == 0 {
            record(0..<ua[0].range.lowerBound, 0..<ub[0].range.lowerBound)
        }
        for t in 1..<pairs.count {
            let p = pairs[t - 1]
            let q = pairs[t]
            if q.a == p.a + 1 && q.b == p.b + 1 {
                record(ua[p.a].range.upperBound..<ua[q.a].range.lowerBound,
                       ub[p.b].range.upperBound..<ub[q.b].range.lowerBound)
            }
        }
        if let last = pairs.last, last.a == ua.count - 1, last.b == ub.count - 1 {
            record(ua[last.a].range.upperBound..<aBytes.count,
                   ub[last.b].range.upperBound..<bBytes.count)
        }
        return out
    }
}
