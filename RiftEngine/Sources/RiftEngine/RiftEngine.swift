/// engine-wide limits (nfr-2, sdd §6.4, §6.5)
enum EngineLimits {
    /// utf-8 bytes per side above which refinement degrades to unit granularity
    static let softCap = 1_000_000
    /// utf-8 bytes per side above which only a coarse block result is produced
    static let hardCap = 4_000_000
    /// unit count from which the pathology guard may engage
    static let pathologyMinUnits = 100
    /// common-unit ratio below which alignment degrades to prefix/suffix only
    static let pathologyCommonRatio = 0.15
    /// dice similarity at or above which a delete/insert pair is a modification
    static let dicePairingThreshold = 0.3
    /// characters per unit beyond which intra-unit refinement is skipped
    static let refineCharCap = 10_000
    /// characters per word beyond which character-level refinement is skipped
    static let charPolishCap = 200
}

/// public facade of the diff engine (sdd §5.2): a pure, synchronous,
/// deterministic function of value types — no ui, no i/o, no dependencies
public enum RiftEngine {
    /// compares two texts and reports what actually changed (sdd §3).
    /// runs the full strictness ladder, detection, alignment, refinement, and
    /// formatting accounting; every difference set aside is counted and carries
    /// provenance back to the originals — never silently discarded
    public static func compare(
        _ a: String,
        _ b: String,
        options: CompareOptions = .init()
    ) -> DiffReport {
        if let report = pipeline(a, b, options: options, isCancelled: { false }) {
            return report
        }
        // unreachable (the closure never cancels); total fallback kept for safety
        let equal = a.utf8.count == b.utf8.count && a.utf8.elementsEqual(b.utf8)
        let profile = DetectedProfile(profile: .plain, isAutomatic: true, confidence: 0,
                                      isIndentationSensitive: false, explanation: "fallback")
        let ladder = StrictnessLevel.allCases.map {
            LadderLevelResult(level: $0, isEqual: equal, resolvedSiteCount: 0)
        }
        let document = DiffDocument(hunks: [], isDegraded: false, degradationReason: nil)
        return DiffReport(verdict: equal ? .identical : .changed(contentChanges: 1, formattingOnly: 0),
                          profile: profile, ladder: ladder, document: document)
    }

    /// cancellable variant (sdd §5.4): the closure is checked between pipeline
    /// stages; once it returns true the call returns nil and no partial report
    /// is ever published (sdd §9)
    public static func compare(
        _ a: String,
        _ b: String,
        options: CompareOptions,
        isCancelled: () -> Bool
    ) -> DiffReport? {
        pipeline(a, b, options: options, isCancelled: isCancelled)
    }

    // MARK: - pipeline

    private static func levelFrom(_ raw: Int) -> StrictnessLevel {
        switch raw {
        case 0: return .exact
        case 1: return .encoding
        case 2: return .spacing
        default: return .layout
        }
    }

    private static func pipeline(_ a: String, _ b: String, options: CompareOptions,
                                 isCancelled: () -> Bool) -> DiffReport? {
        let rules: RuleSet
        switch options.mode {
        case .custom(let custom):
            rules = custom
        case .smart, .strict:
            rules = RuleSet()
        }
        let isStrict: Bool
        if case .strict = options.mode {
            isStrict = true
        } else {
            isStrict = false
        }

        let detected = ContentDetector.detect(a, b, override: options.profileOverride)
        if isCancelled() { return nil }
        let profile = detected.profile
        let sensitive = detected.isIndentationSensitive

        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        let overHard = aBytes.count > EngineLimits.hardCap || bBytes.count > EngineLimits.hardCap
        let overSoft = aBytes.count > EngineLimits.softCap || bBytes.count > EngineLimits.softCap

        // ladder equality (sdd §6.4): l0 is byte-for-byte; higher levels compare
        // canonical forms
        var equalAt = [Bool](repeating: false, count: 4)
        equalAt[0] = aBytes == bBytes
        for level in 1...3 {
            // codepoint-exact comparison of canonical forms (never String ==,
            // whose canonical equivalence would blur levels)
            equalAt[level] = Normalizer.utf8Equal(
                Normalizer.canonicalString(a, level: level, profile: profile,
                                           rules: rules, sensitive: sensitive),
                Normalizer.canonicalString(b, level: level, profile: profile,
                                           rules: rules, sensitive: sensitive))
        }
        if isCancelled() { return nil }

        let effectiveLevels: [Int] = isStrict ? [0] : [0, 1, 2, 3]
        var convergence: Int?
        for level in effectiveLevels where equalAt[level] {
            convergence = level
            break
        }

        // strict mode diffs the raw line structure (sdd fr-5)
        let unitRules = isStrict ? RuleSet.allOff : rules
        let unitProfile: Profile = isStrict ? .plain : profile
        let unitSensitive = isStrict ? false : sensitive
        let ua = Normalizer.buildUnits(a, profile: unitProfile, rules: unitRules, sensitive: unitSensitive)
        let ub = Normalizer.buildUnits(b, profile: unitProfile, rules: unitRules, sensitive: unitSensitive)
        if isCancelled() { return nil }

        var rawHunks: [Refiner.RawHunk] = []
        var contentChanges = 0
        var rawSites: [FormattingAccountant.RawSite] = []
        var degraded = overSoft
        var degradationReason: DegradationReason? = overHard ? .inputTooLarge
            : (overSoft ? .softThreshold : nil)
        let verdict: Verdict

        if convergence == 0 {
            verdict = .identical
            if !ua.isEmpty && ua.count == ub.count {
                rawHunks = [Refiner.RawHunk(kind: .equal, a: 0..<ua.count, b: 0..<ub.count)]
            }
        } else if let conv = convergence {
            // converged above l0: unit streams are 1:1 by construction
            let count = min(ua.count, ub.count)
            let allPairs = (0..<count).map {
                FormattingAccountant.AlignedPair(a: $0, b: $0, isContent: false)
            }
            let raw = FormattingAccountant.sites(aBytes: aBytes, bBytes: bBytes,
                                                 ua: ua, ub: ub, pairs: allPairs,
                                                 profile: profile, rules: rules,
                                                 sensitive: sensitive)
            // a slice out of context can look like it needs a higher level than the
            // document did (an eof newline reads as a blank line); the document's
            // convergence level bounds every site (sdd §9)
            rawSites = raw.map {
                FormattingAccountant.RawSite(level: min($0.level, conv),
                                             rangeA: $0.rangeA, rangeB: $0.rangeB)
            }
            verdict = .formattingOnly(level: levelFrom(conv), count: rawSites.count)
            if !ua.isEmpty {
                rawHunks = [Refiner.RawHunk(kind: .equal, a: 0..<ua.count, b: 0..<ub.count)]
            }
        } else if overHard {
            rawHunks = [Refiner.RawHunk(kind: .modification, a: 0..<ua.count, b: 0..<ub.count)]
            contentChanges = 1
            verdict = .changed(contentChanges: 1, formattingOnly: 0)
        } else {
            let textsA = ua.map(\.text)
            let textsB = ub.map(\.text)
            var pathological = false
            if max(ua.count, ub.count) >= EngineLimits.pathologyMinUnits,
               Aligner.commonUnitRatio(textsA, textsB) < EngineLimits.pathologyCommonRatio {
                pathological = true
                degraded = true
                degradationReason = .pathologicalInput
            }
            if pathological {
                let ops = Aligner.prefixSuffixOnly(textsA, textsB)
                (rawHunks, contentChanges) = coarseHunks(ops)
            } else {
                let ops = Aligner.align(textsA, textsB)
                if isCancelled() { return nil }
                (rawHunks, contentChanges) = Refiner.buildRawHunks(ua: ua, ub: ub, ops: ops,
                                                                   profile: unitProfile)
            }
            if isStrict {
                rawSites = []  // strict shows everything; nothing is set aside
            } else {
                rawSites = FormattingAccountant.sites(
                    aBytes: aBytes, bBytes: bBytes, ua: ua, ub: ub,
                    pairs: FormattingAccountant.pairs(from: rawHunks),
                    profile: profile, rules: rules, sensitive: sensitive)
            }
            verdict = .changed(contentChanges: contentChanges, formattingOnly: rawSites.count)
        }
        if isCancelled() { return nil }

        var ladder: [LadderLevelResult] = []
        for level in 0...3 {
            let resolved = level > 0 ? rawSites.filter { $0.level == level }.count : 0
            ladder.append(LadderLevelResult(level: levelFrom(level),
                                            isEqual: equalAt[level],
                                            resolvedSiteCount: resolved))
        }

        // public sites in document order with provenance (fr-10); recording
        // order interleaves paired units and gaps, so sort by ranges — the sort
        // keys are disjoint windows, making the order total and deterministic
        let sites = rawSites
            .sorted {
                if $0.rangeA.lowerBound != $1.rangeA.lowerBound {
                    return $0.rangeA.lowerBound < $1.rangeA.lowerBound
                }
                if $0.rangeA.upperBound != $1.rangeA.upperBound {
                    return $0.rangeA.upperBound < $1.rangeA.upperBound
                }
                return $0.rangeB.lowerBound < $1.rangeB.lowerBound
            }
            .map { FormattingSite(level: levelFrom($0.level), rangeA: $0.rangeA, rangeB: $0.rangeB) }

        let hunks = materialize(rawHunks, ua: ua, ub: ub,
                                totalA: aBytes.count, totalB: bBytes.count,
                                suppressSegments: degraded, profile: unitProfile)
        let document = DiffDocument(hunks: hunks, isDegraded: degraded,
                                    degradationReason: degradationReason)
        return DiffReport(verdict: verdict, profile: detected, ladder: ladder,
                          sites: sites, document: document)
    }

    /// coarse block result for pathological inputs (sdd §6.4): equal prefix and
    /// suffix, one change hunk in between, no pairing
    private static func coarseHunks(_ ops: [Aligner.AlignOp]) -> ([Refiner.RawHunk], Int) {
        var hunks: [Refiner.RawHunk] = []
        var deleteOp: (start: Int, count: Int)?
        var insertOp: (start: Int, count: Int)?
        for op in ops {
            switch op {
            case let .equal(a, b, count):
                hunks.append(Refiner.RawHunk(kind: .equal, a: a..<(a + count), b: b..<(b + count)))
            case let .delete(a, count):
                deleteOp = (a, count)
            case let .insert(b, count):
                insertOp = (b, count)
            }
        }
        if deleteOp == nil && insertOp == nil {
            return (hunks, 0)
        }
        let a0 = deleteOp?.start ?? insertOp?.start ?? 0
        let aRange = a0..<(a0 + (deleteOp?.count ?? 0))
        let b0 = insertOp?.start ?? a0
        let bRange = b0..<(b0 + (insertOp?.count ?? 0))
        let kind: HunkKind
        if deleteOp != nil && insertOp != nil {
            kind = .modification
        } else if deleteOp != nil {
            kind = .deletion
        } else {
            kind = .insertion
        }
        var insertAt = 0
        if let first = hunks.first, first.a.lowerBound == 0, !first.a.isEmpty {
            insertAt = 1
        }
        hunks.insert(Refiner.RawHunk(kind: kind, a: aRange, b: bRange), at: insertAt)
        return (hunks, 1)
    }

    // MARK: - materialization

    /// converts internal index-range hunks to the public document. hunk byte
    /// ranges tile each original exactly — concatenating the slices reconstructs
    /// both inputs (sdd §10 property) — with gap bytes assigned to the hunk that
    /// follows their preceding boundary
    private static func materialize(_ raw: [Refiner.RawHunk], ua: [Unit], ub: [Unit],
                                    totalA: Int, totalB: Int,
                                    suppressSegments: Bool, profile: Profile) -> [Hunk] {
        if raw.isEmpty {
            return [Hunk(kind: .equal, unitsA: [], unitsB: [], segments: [],
                         rangeA: 0..<totalA, rangeB: 0..<totalB)]
        }
        let rangesA = tileRanges(raw.map(\.a), units: ua, total: totalA)
        let rangesB = tileRanges(raw.map(\.b), units: ub, total: totalB)
        var out: [Hunk] = []
        out.reserveCapacity(raw.count)
        for i in 0..<raw.count {
            let h = raw[i]
            var segments: [Segment] = []
            if h.kind == .modification, h.a.count == 1, h.b.count == 1, !suppressSegments {
                segments = Refiner.segments(unitA: ua[h.a.lowerBound],
                                            unitB: ub[h.b.lowerBound], profile: profile)
            }
            out.append(Hunk(kind: h.kind,
                            unitsA: Array(ua[h.a]), unitsB: Array(ub[h.b]),
                            segments: segments,
                            rangeA: rangesA[i], rangeB: rangesB[i]))
        }
        return out
    }

    private static func tileRanges(_ indexRanges: [Range<Int>], units: [Unit],
                                   total: Int) -> [Range<Int>] {
        var out: [Range<Int>] = []
        out.reserveCapacity(indexRanges.count)
        var cursor = 0
        for i in 0..<indexRanges.count {
            let start = cursor
            let contentEnd: Int
            if indexRanges[i].isEmpty {
                contentEnd = start
            } else {
                contentEnd = units[indexRanges[i].upperBound - 1].range.upperBound
            }
            var end: Int
            if i + 1 < indexRanges.count {
                let next = indexRanges[i + 1]
                if next.isEmpty {
                    end = contentEnd
                } else {
                    end = units[next.lowerBound].range.lowerBound
                }
                end = max(end, contentEnd)
                end = max(end, start)
            } else {
                end = max(total, contentEnd)
            }
            out.append(start..<end)
            cursor = end
        }
        return out
    }
}
