/// options for a comparison (sdd §5.2)
public struct CompareOptions: Sendable, Hashable {
    /// comparison mode (sdd §4.1 FR-5); `.custom(RuleSet)` arrives with M1
    public enum Mode: Sendable, Hashable {
        case smart
        case strict
    }

    public var mode: Mode
    /// nil = auto-detect (sdd §3.3)
    public var profileOverride: Profile?

    public init(mode: Mode = .smart, profileOverride: Profile? = nil) {
        self.mode = mode
        self.profileOverride = profileOverride
    }
}
