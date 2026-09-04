/// levels of the strictness ladder (sdd §3.2); cumulative, raw value is the level number
public enum StrictnessLevel: Int, Sendable, Hashable, Codable, CaseIterable, Comparable {
    case exact = 0    // L0 — texts as given
    case encoding = 1 // L1 — line endings, nfc, invisibles, trailing whitespace, eof newline
    case spacing = 2  // L2 — space/tab runs, blank-line runs, nbsp, typographic equivalence
    case layout = 3   // L3 — prose reflow, code indentation

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// display label: "L0" through "L3"
    public var label: String {
        "L\(rawValue)"
    }
}

/// which profile was applied, how sure the detector was, and why (sdd §3.3, §6.2)
public struct DetectedProfile: Sendable, Hashable {
    public let profile: Profile
    public let isAutomatic: Bool
    public let confidence: Double
    /// code only: indentation looks meaning-bearing, so l3 keeps it (sdd §3.3, r-8)
    public let isIndentationSensitive: Bool
    /// one line of detector reasoning for the inspector
    public let explanation: String

    public init(profile: Profile, isAutomatic: Bool, confidence: Double,
                isIndentationSensitive: Bool, explanation: String) {
        self.profile = profile
        self.isAutomatic = isAutomatic
        self.confidence = confidence
        self.isIndentationSensitive = isIndentationSensitive
        self.explanation = explanation
    }
}

/// one row of the ladder readout: was the pair equal at this level, and how many
/// formatting-only sites are attributed to exactly this level (sdd §3.4, §6.6)
public struct LadderLevelResult: Sendable, Hashable {
    public let level: StrictnessLevel
    public let isEqual: Bool
    public let resolvedSiteCount: Int

    public init(level: StrictnessLevel, isEqual: Bool, resolvedSiteCount: Int) {
        self.level = level
        self.isEqual = isEqual
        self.resolvedSiteCount = resolvedSiteCount
    }
}

/// one formatting-only difference with provenance (sdd §3.4, §6.6, fr-10): the
/// utf-8 byte ranges of the differing raw slices in each ORIGINAL string,
/// attributed to the lowest ladder level whose canonicalization resolves the
/// difference. `level` is never `.exact`; either range may be empty (bytes
/// present on one side only, e.g. a trailing eof newline)
public struct FormattingSite: Sendable, Hashable {
    public let level: StrictnessLevel
    public let rangeA: Range<Int>
    public let rangeB: Range<Int>

    public init(level: StrictnessLevel, rangeA: Range<Int>, rangeB: Range<Int>) {
        self.level = level
        self.rangeA = rangeA
        self.rangeB = rangeB
    }
}

/// the banner-level outcome of a comparison (sdd §3.4)
public enum Verdict: Sendable, Hashable {
    /// equal at l0, byte-for-byte
    case identical
    /// equal at `level`; `count` formatting-only differences were set aside (and remain revealable)
    case formattingOnly(level: StrictnessLevel, count: Int)
    /// `contentChanges` substantive changes plus `formattingOnly` formatting-only differences
    case changed(contentChanges: Int, formattingOnly: Int)
}

/// everything the ui needs to render a comparison; the app never computes (sdd §5.2)
public struct DiffReport: Sendable, Hashable {
    public let verdict: Verdict
    public let profile: DetectedProfile
    /// all four levels, in ladder order
    public let ladder: [LadderLevelResult]
    /// every formatting-only site with provenance, in document order (fr-10);
    /// `sites.count` always equals the verdict's formatting-only count
    public let sites: [FormattingSite]
    public let document: DiffDocument

    public init(verdict: Verdict, profile: DetectedProfile,
                ladder: [LadderLevelResult], sites: [FormattingSite] = [],
                document: DiffDocument) {
        self.verdict = verdict
        self.profile = profile
        self.ladder = ladder
        self.sites = sites
        self.document = document
    }
}
