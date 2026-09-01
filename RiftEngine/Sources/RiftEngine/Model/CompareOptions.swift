/// per-rule toggles backing custom mode (sdd §4.1 fr-5, appendix a).
/// leveled rules default on (the smart ladder); the two meaning-changing
/// rules default off and never join the ladder (sdd §3.2)
public struct RuleSet: Sendable, Hashable {
    // l1 — encoding
    public var unicodeNFC = true
    public var stripInvisibles = true
    public var stripTrailingWhitespace = true
    // l2 — spacing
    public var collapseSpaceRuns = true
    public var collapseBlankLines = true
    public var trimOuterBlankLines = true
    public var nbspToSpace = true
    public var typographicEquivalence = true  // prose only
    // l3 — layout
    public var reflowProse = true             // prose
    public var ignoreIndentation = true       // code, unless indentation-sensitive
    public var ignoreBlankLinesEntirely = true // code, unless indentation-sensitive
    // meaning-changing opt-ins (custom mode only)
    public var ignoreCase = false
    public var ignorePunctuation = false

    public init() {}

    /// every leveled rule off: the raw-structure view strict mode diffs with
    public static let allOff: RuleSet = {
        var r = RuleSet()
        r.unicodeNFC = false
        r.stripInvisibles = false
        r.stripTrailingWhitespace = false
        r.collapseSpaceRuns = false
        r.collapseBlankLines = false
        r.trimOuterBlankLines = false
        r.nbspToSpace = false
        r.typographicEquivalence = false
        r.reflowProse = false
        r.ignoreIndentation = false
        r.ignoreBlankLinesEntirely = false
        return r
    }()
}

/// options for a comparison (sdd §5.2)
public struct CompareOptions: Sendable, Hashable {
    /// comparison mode (sdd §4.1 fr-5)
    public enum Mode: Sendable, Hashable {
        /// the full strictness ladder with default rules
        case smart
        /// l0 only: show everything, set nothing aside
        case strict
        /// the ladder evaluated with the given rule toggles
        case custom(RuleSet)
    }

    public var mode: Mode
    /// nil = auto-detect (sdd §3.3)
    public var profileOverride: Profile?

    public init(mode: Mode = .smart, profileOverride: Profile? = nil) {
        self.mode = mode
        self.profileOverride = profileOverride
    }
}
