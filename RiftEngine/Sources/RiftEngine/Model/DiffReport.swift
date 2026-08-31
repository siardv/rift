/// levels of the strictness ladder (sdd §3.2); cumulative, raw value is the level number
public enum StrictnessLevel: Int, Sendable, Hashable, Codable, CaseIterable, Comparable {
    case exact = 0    // L0 — texts as given
    case encoding = 1 // L1 — line endings, nfc, bom, trailing whitespace, eof newline
    case spacing = 2  // L2 — space/tab runs, blank-line runs, nbsp, typographic equivalence
    case layout = 3   // L3 — prose reflow, code indentation

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// which profile was applied and whether detection or an override chose it (sdd §3.3, §5.2)
/// m1 adds the detector's score summary ("why")
public struct DetectedProfile: Sendable, Hashable {
    public let profile: Profile
    public let isAutomatic: Bool

    public init(profile: Profile, isAutomatic: Bool) {
        self.profile = profile
        self.isAutomatic = isAutomatic
    }
}

/// one row of the ladder readout: was the pair equal at this level,
/// and how many formatting-only sites this level resolved (sdd §3.4, §6.6)
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

/// the banner-level outcome of a comparison (sdd §3.4)
public enum Verdict: Sendable, Hashable {
    /// equal at L0, byte-for-byte
    case identical
    /// equal at `level`; `count` formatting-only differences were set aside (and remain revealable)
    case formattingOnly(level: StrictnessLevel, count: Int)
    /// `contentChanges` substantive changes plus `formattingOnly` formatting-only differences
    case changed(contentChanges: Int, formattingOnly: Int)
}

/// everything the ui needs to render a comparison; the app never computes (sdd §5.2)
/// m0 stub shape — m1 adds `document: DiffDocument` (ordered hunks with provenance)
public struct DiffReport: Sendable, Hashable {
    public let verdict: Verdict
    public let profile: DetectedProfile
    /// levels actually evaluated, in ladder order
    public let ladder: [LadderLevelResult]

    public init(verdict: Verdict, profile: DetectedProfile, ladder: [LadderLevelResult]) {
        self.verdict = verdict
        self.profile = profile
        self.ladder = ladder
    }
}
