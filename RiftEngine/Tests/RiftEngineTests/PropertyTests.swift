import XCTest
@testable import RiftEngine

/// deterministic seeded generator so property tests are reproducible everywhere
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// property tests per sdd §10: identity, idempotence, monotonicity, provenance,
/// and hunk-range reconstruction
final class PropertyTests: XCTestCase {
    private static let pieces: [String] = [
        "a", "b", "word", "fox", "colour", "\u{E9}", "e\u{301}", "\u{1F44D}\u{1F3FD}",
        " ", "  ", "\t", "\n", "\n\n", "\r\n", "\r", "\u{A0}", "\u{200B}", "\u{FEFF}", "\u{AD}",
        "\u{2014}", "\u{201C}q\u{201D}", "\u{2026}", ".", ",", ";", "{", "}", "(", ")", "=", ":",
        "#", "-", "0", "def", "let", "return", "The end.", "x = 1;",
    ]
    private static let iterations = 250

    private func randomText(_ rng: inout SplitMix64, maxPieces: UInt64 = 50) -> String {
        let count = Int(rng.next() % maxPieces)
        var out = ""
        for _ in 0..<count {
            out += Self.pieces[Int(rng.next() % UInt64(Self.pieces.count))]
        }
        return out
    }

    func testCompareOfEqualInputsIsIdenticalInEveryMode() {
        var rng = SplitMix64(seed: 20_260_831)
        for _ in 0..<Self.iterations {
            let x = randomText(&rng)
            XCTAssertEqual(RiftEngine.compare(x, x).verdict, .identical)
            XCTAssertEqual(RiftEngine.compare(x, x, options: .init(mode: .strict)).verdict, .identical)
            var rules = RuleSet()
            rules.collapseSpaceRuns = rng.next() % 2 == 0
            rules.typographicEquivalence = rng.next() % 2 == 0
            rules.reflowProse = rng.next() % 2 == 0
            rules.ignoreCase = rng.next() % 2 == 0
            XCTAssertEqual(RiftEngine.compare(x, x, options: .init(mode: .custom(rules))).verdict,
                           .identical)
        }
    }

    func testCanonicalizationIsIdempotentPerLevel() {
        var rng = SplitMix64(seed: 7)
        let rules = RuleSet()
        for _ in 0..<Self.iterations {
            let x = randomText(&rng)
            for profile in Profile.allCases {
                for level in 1...3 {
                    let once = Normalizer.canonicalString(x, level: level, profile: profile,
                                                          rules: rules, sensitive: false)
                    let twice = Normalizer.canonicalString(once, level: level, profile: profile,
                                                           rules: rules, sensitive: false)
                    XCTAssertEqual(once, twice,
                                   "level \(level) \(profile.rawValue) not idempotent for \(x.debugDescription)")
                }
            }
        }
    }

    func testLadderMonotoneAndCountsCoherent() {
        var rng = SplitMix64(seed: 99)
        for _ in 0..<Self.iterations {
            let x = randomText(&rng)
            let y = randomText(&rng)
            let report = RiftEngine.compare(x, y)
            let equal = report.ladder.map(\.isEqual)
            for i in 0..<3 {
                XCTAssertTrue(!equal[i] || equal[i + 1],
                              "ladder must be monotone for \(x.debugDescription) vs \(y.debugDescription)")
            }
            let resolvedTotal = report.ladder.map(\.resolvedSiteCount).reduce(0, +)
            switch report.verdict {
            case .identical:
                XCTAssertEqual(Array(x.utf8), Array(y.utf8))
                XCTAssertEqual(resolvedTotal, 0)
            case let .formattingOnly(level, count):
                XCTAssertGreaterThanOrEqual(count, 1)
                XCTAssertGreaterThanOrEqual(level, .encoding)
                XCTAssertEqual(resolvedTotal, count)
            case let .changed(k, m):
                XCTAssertGreaterThanOrEqual(k, 1)
                XCTAssertEqual(resolvedTotal, m)
            }
        }
    }

    func testProvenanceInvariants() {
        var rng = SplitMix64(seed: 424_242)
        let rules = RuleSet()
        for _ in 0..<Self.iterations {
            let x = randomText(&rng)
            let byteCount = x.utf8.count
            for profile in Profile.allCases {
                let units = Normalizer.buildUnits(x, profile: profile, rules: rules, sensitive: false)
                var previousEnd = 0
                for unit in units {
                    XCTAssertTrue(unit.range.lowerBound >= previousEnd,
                                  "units must be ordered and non-overlapping")
                    XCTAssertTrue(unit.range.upperBound <= byteCount, "unit range in bounds")
                    previousEnd = unit.range.upperBound
                    var tokenPrevEnd = unit.range.lowerBound
                    for token in unit.tokens {
                        XCTAssertTrue(token.range.lowerBound >= tokenPrevEnd
                                      && token.range.upperBound <= unit.range.upperBound,
                                      "token inside unit, ordered")
                        tokenPrevEnd = token.range.upperBound
                    }
                    if profile == .prose {
                        XCTAssertEqual(unit.text, unit.tokens.map(\.text).joined(separator: " "),
                                       "prose unit text is its joined tokens")
                    }
                }
            }
        }
    }

    func testHunkRangesTileBothOriginals() {
        var rng = SplitMix64(seed: 31_337)
        for _ in 0..<Self.iterations {
            let x = randomText(&rng)
            let y = randomText(&rng)
            let report = RiftEngine.compare(x, y)
            let bytesA = Array(x.utf8)
            let bytesB = Array(y.utf8)
            var rebuiltA: [UInt8] = []
            var rebuiltB: [UInt8] = []
            var cursorA = 0
            var cursorB = 0
            for hunk in report.document.hunks {
                XCTAssertEqual(hunk.rangeA.lowerBound, cursorA, "hunk ranges must be contiguous on a")
                XCTAssertEqual(hunk.rangeB.lowerBound, cursorB, "hunk ranges must be contiguous on b")
                rebuiltA.append(contentsOf: bytesA[hunk.rangeA])
                rebuiltB.append(contentsOf: bytesB[hunk.rangeB])
                cursorA = hunk.rangeA.upperBound
                cursorB = hunk.rangeB.upperBound
            }
            XCTAssertEqual(rebuiltA, bytesA, "concatenated hunk ranges must reconstruct a")
            XCTAssertEqual(rebuiltB, bytesB, "concatenated hunk ranges must reconstruct b")
        }
    }
}
