/// public facade of the diff engine (sdd §5.2): a pure, synchronous,
/// deterministic function of value types — no ui, no i/o, no dependencies
public enum RiftEngine {
    /// compares two texts and reports what actually changed.
    ///
    /// m0 stub: evaluates only L0 (byte equality). the full ladder (sdd §3.2),
    /// profile detection (§3.3), alignment, refinement, and formatting
    /// accounting (§6) land with M1. placeholder semantics until then:
    /// equal inputs → `.identical`; anything else is reported as one aggregate
    /// content change with zero formatting accounting.
    public static func compare(
        _ a: String,
        _ b: String,
        options: CompareOptions = .init()
    ) -> DiffReport {
        // L0 is byte-for-byte (sdd §3.4), so compare utf-8 units directly;
        // swift's `==` on String uses canonical equivalence, which already
        // blurs into L1 (nfc) territory
        let equalAtL0 = a.utf8.count == b.utf8.count && a.utf8.elementsEqual(b.utf8)

        let profile = DetectedProfile(
            profile: options.profileOverride ?? .plain,
            isAutomatic: options.profileOverride == nil
        )
        let ladder = [
            LadderLevelResult(level: .exact, isEqual: equalAtL0, resolvedSiteCount: 0)
        ]
        let verdict: Verdict = equalAtL0
            ? .identical
            : .changed(contentChanges: 1, formattingOnly: 0)

        return DiffReport(verdict: verdict, profile: profile, ladder: ladder)
    }
}
