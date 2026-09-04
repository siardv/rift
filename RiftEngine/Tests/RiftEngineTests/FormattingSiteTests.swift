import XCTest
import RiftEngine

/// m2 addendum tests (fr-10): DiffReport.sites carries every formatting-only
/// site with provenance ranges. self-contained on purpose — seeded generator
/// included here rather than reusing m1 test helpers.
/// equality on content is always byte-level in these tests (m1 erratum:
/// swift's String == is canonical equivalence and would blur nfc differences)
final class FormattingSiteTests: XCTestCase {

    // MARK: - seeded deterministic generator (splitmix64)

    private struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// pieces chosen to exercise every ladder level: plain words, space runs,
    /// tabs, blank-line runs, nbsp, curly quotes, dashes, nfc/nfd pair, crlf,
    /// trailing spaces, zero-width space
    private static let pieces: [String] = [
        "alpha", "beta", "gamma one", "delta,", "epsilon.",
        " ", "  ", "\t", "\n", "\n\n", "\n\n\n", "\r\n",
        "\u{00A0}", "\u{201C}q\u{201D}", "\"q\"", "\u{2014}", "-", "...",
        "caf\u{E9}", "cafe\u{301}", "x \n", "  indented", "\u{200B}",
    ]

    private func makeText(_ rng: inout SplitMix64) -> String {
        let count = Int(rng.next() % 24)
        var out = ""
        for _ in 0..<count {
            out += Self.pieces[Int(rng.next() % UInt64(Self.pieces.count))]
        }
        return out
    }

    /// b is either an independent text or a mutated copy of a
    private func makePair(_ rng: inout SplitMix64) -> (String, String) {
        let a = makeText(&rng)
        switch rng.next() % 4 {
        case 0:
            return (a, makeText(&rng))
        case 1:
            return (a, a + Self.pieces[Int(rng.next() % UInt64(Self.pieces.count))])
        case 2:
            // piece-level substitution: rebuild with one piece swapped
            var rng2 = SplitMix64(state: rng.state)
            var b = makeText(&rng2)
            b += "  "
            return (a, b)
        default:
            return (a, a)
        }
    }

    private func formattingCount(of verdict: Verdict) -> Int {
        switch verdict {
        case .identical:
            return 0
        case .formattingOnly(_, let count):
            return count
        case .changed(_, let formattingOnly):
            return formattingOnly
        }
    }

    // MARK: - invariants (property tests)

    private func assertSiteInvariants(_ a: String, _ b: String, options: CompareOptions,
                                      seed: UInt64, line: UInt = #line) {
        let report = RiftEngine.compare(a, b, options: options)
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)

        // count: sites always mirrors the verdict's formatting-only count
        XCTAssertEqual(report.sites.count, formattingCount(of: report.verdict),
                       "seed \(seed): site count vs verdict", line: line)

        // per-level counts match the ladder readout; no site at l0
        for row in report.ladder where row.level > .exact {
            let atLevel = report.sites.filter { $0.level == row.level }.count
            XCTAssertEqual(atLevel, row.resolvedSiteCount,
                           "seed \(seed): ladder \(row.level.label)", line: line)
        }
        XCTAssertTrue(report.sites.allSatisfy { $0.level > .exact },
                      "seed \(seed): no l0 sites", line: line)

        var previous: FormattingSite?
        for site in report.sites {
            // bounds
            XCTAssertGreaterThanOrEqual(site.rangeA.lowerBound, 0, line: line)
            XCTAssertLessThanOrEqual(site.rangeA.upperBound, aBytes.count,
                                     "seed \(seed): rangeA in bounds", line: line)
            XCTAssertGreaterThanOrEqual(site.rangeB.lowerBound, 0, line: line)
            XCTAssertLessThanOrEqual(site.rangeB.upperBound, bBytes.count,
                                     "seed \(seed): rangeB in bounds", line: line)
            // the raw slices really differ, byte for byte
            XCTAssertFalse(aBytes[site.rangeA].elementsEqual(bBytes[site.rangeB]),
                           "seed \(seed): slices differ", line: line)
            // document order, non-overlapping windows on both sides
            if let p = previous {
                XCTAssertLessThanOrEqual(p.rangeA.upperBound, site.rangeA.lowerBound,
                                         "seed \(seed): a-side ordered", line: line)
                XCTAssertLessThanOrEqual(p.rangeB.upperBound, site.rangeB.lowerBound,
                                         "seed \(seed): b-side ordered", line: line)
            }
            previous = site
        }
    }

    func testSiteInvariantsSmartModeSeeded() {
        var rng = SplitMix64(state: 0x51AD_0001)
        for i in 0..<150 {
            let (a, b) = makePair(&rng)
            assertSiteInvariants(a, b, options: CompareOptions(mode: .smart), seed: UInt64(i))
        }
    }

    func testSiteInvariantsCustomModeSeeded() {
        var rng = SplitMix64(state: 0x51AD_0002)
        var rules = RuleSet()
        rules.typographicEquivalence = false
        rules.collapseBlankLines = false
        for i in 0..<100 {
            let (a, b) = makePair(&rng)
            assertSiteInvariants(a, b, options: CompareOptions(mode: .custom(rules)), seed: UInt64(i))
        }
    }

    func testStrictModeNeverReportsSites() {
        var rng = SplitMix64(state: 0x51AD_0003)
        for _ in 0..<100 {
            let (a, b) = makePair(&rng)
            let report = RiftEngine.compare(a, b, options: CompareOptions(mode: .strict))
            XCTAssertTrue(report.sites.isEmpty)
            XCTAssertEqual(formattingCount(of: report.verdict), 0)
        }
    }

    func testIdenticalInputsHaveNoSites() {
        var rng = SplitMix64(state: 0x51AD_0004)
        for _ in 0..<50 {
            let a = makeText(&rng)
            let report = RiftEngine.compare(a, a)
            XCTAssertEqual(report.verdict, .identical)
            XCTAssertTrue(report.sites.isEmpty)
        }
    }

    // MARK: - known cases (unit tests)

    func testEofNewlineSiteCarriesL1Provenance() {
        let report = RiftEngine.compare("x\n", "x")
        guard case .formattingOnly(let level, let count) = report.verdict else {
            return XCTFail("expected formattingOnly, got \(report.verdict)")
        }
        XCTAssertEqual(level, .encoding)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(report.sites.count, 1)
        let site = report.sites[0]
        XCTAssertEqual(site.level, .encoding)
        XCTAssertEqual(site.rangeA, 1..<2) // the "\n" byte in a
        XCTAssertEqual(site.rangeB, 1..<1) // empty on b's side
    }

    func testSpaceRunSiteCarriesL2Provenance() {
        let report = RiftEngine.compare("a  b\n", "a b\n")
        XCTAssertEqual(report.sites.count, formattingCount(of: report.verdict))
        XCTAssertEqual(report.sites.count, 1)
        let site = report.sites[0]
        XCTAssertEqual(site.level, .spacing)
        // the differing raw slices are the whole first lines
        XCTAssertEqual(site.rangeA, 0..<4)
        XCTAssertEqual(site.rangeB, 0..<3)
    }

    func testMultipleSitesArriveInDocumentOrderWithMatchingLadder() {
        let a = "one\ntwo  x\nthree \n"
        let b = "one\ntwo x\nthree\n"
        let report = RiftEngine.compare(a, b)
        XCTAssertEqual(report.sites.count, formattingCount(of: report.verdict))
        XCTAssertEqual(report.sites.count, 2)
        // doc order: the space-run line (l2) precedes the trailing-space line (l1)
        XCTAssertEqual(report.sites[0].level, .spacing)
        XCTAssertEqual(report.sites[1].level, .encoding)
        XCTAssertLessThanOrEqual(report.sites[0].rangeA.upperBound,
                                 report.sites[1].rangeA.lowerBound)
        let l1 = report.ladder.first { $0.level == .encoding }
        let l2 = report.ladder.first { $0.level == .spacing }
        XCTAssertEqual(l1?.resolvedSiteCount, 1)
        XCTAssertEqual(l2?.resolvedSiteCount, 1)
    }

    func testNFCOnlySiteIsL1AndSlicesDifferByBytes() {
        // canonical-equivalence trap from the m1 erratum: "café" nfc vs nfd
        let report = RiftEngine.compare("caf\u{E9}\n", "cafe\u{301}\n")
        XCTAssertEqual(report.sites.count, 1)
        XCTAssertEqual(report.sites[0].level, .encoding)
        let aBytes = Array("caf\u{E9}\n".utf8)
        let bBytes = Array("cafe\u{301}\n".utf8)
        XCTAssertFalse(aBytes[report.sites[0].rangeA].elementsEqual(bBytes[report.sites[0].rangeB]))
    }
}
