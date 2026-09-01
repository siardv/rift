import XCTest
@testable import RiftEngine

final class RiftEngineTests: XCTestCase {
    // MARK: - m0 contract, still holding

    func testIdenticalInputsReportIdentical() {
        let report = RiftEngine.compare("The quick brown fox.", "The quick brown fox.")
        XCTAssertEqual(report.verdict, .identical)
        XCTAssertEqual(report.ladder.first?.isEqual, true)
    }

    func testEmptyInputsReportIdentical() {
        XCTAssertEqual(RiftEngine.compare("", "").verdict, .identical)
    }

    func testDifferingInputsDoNotReportIdentical() {
        XCTAssertNotEqual(RiftEngine.compare("colour", "color").verdict, .identical)
    }

    func testL0IsByteStrict() {
        // precomposed "é" vs "e" + combining acute: canonically equivalent, so l1
        // resolves it — but l0 is byte-exact (sdd §3.4)
        let report = RiftEngine.compare("caf\u{E9}", "cafe\u{301}")
        XCTAssertNotEqual(report.verdict, .identical)
        XCTAssertEqual(report.verdict, .formattingOnly(level: .encoding, count: 1))
    }

    func testProfileOverrideIsRespected() {
        let report = RiftEngine.compare("a", "a", options: .init(profileOverride: .code))
        XCTAssertEqual(report.profile.profile, .code)
        XCTAssertFalse(report.profile.isAutomatic)
    }

    // MARK: - m1 behavior

    func testReflowConvergesAtLayout() {
        // the founding use case (sdd §3.5)
        let report = RiftEngine.compare("The quick brown fox\njumps over the lazy dog.\n",
                                        "The quick brown fox jumps over the lazy dog.\n")
        XCTAssertEqual(report.verdict, .formattingOnly(level: .layout, count: 1))
    }

    func testStrictModeShowsEverything() {
        let report = RiftEngine.compare("The quick brown fox\njumps over the lazy dog.\n",
                                        "The quick brown fox jumps over the lazy dog.\n",
                                        options: .init(mode: .strict))
        guard case let .changed(k, m) = report.verdict else {
            XCTFail("strict mode must not set differences aside; got \(report.verdict)")
            return
        }
        XCTAssertGreaterThanOrEqual(k, 1)
        XCTAssertEqual(m, 0)
        // the ladder still shows where smart mode would converge (inspector readout)
        XCTAssertEqual(report.ladder[3].isEqual, true)
    }

    func testCustomIgnoreCaseResolvesCaseOnlyChange() {
        var rules = RuleSet()
        rules.ignoreCase = true
        let report = RiftEngine.compare("The colour of the banner is deliberate.\n",
                                        "the colour of the banner is deliberate.\n",
                                        options: .init(mode: .custom(rules)))
        guard case .formattingOnly = report.verdict else {
            XCTFail("case-only difference should resolve under ignoreCase; got \(report.verdict)")
            return
        }
    }

    func testCancellationPublishesNothing() {
        let report = RiftEngine.compare("left text", "right text", options: .init(),
                                        isCancelled: { true })
        XCTAssertNil(report)
        let completed = RiftEngine.compare("left text", "right text", options: .init(),
                                           isCancelled: { false })
        XCTAssertNotNil(completed)
    }

    func testRenameProducesOneModificationWithSegments() {
        let a = "const limit = 10;\nfor (const it of items) {\n  push(it);\n}\nflush();\n"
        let b = "const maxItems = 10;\r\nfor (const it of items) {\r\n  push(it);\r\n}\r\nflush();\r\n"
        let report = RiftEngine.compare(a, b)
        guard case let .changed(k, m) = report.verdict else {
            XCTFail("expected changed; got \(report.verdict)")
            return
        }
        XCTAssertEqual(k, 1)
        XCTAssertEqual(m, 5)  // crlf noise, counted not shown (sdd §3.5)
        let mods = report.document.hunks.filter { $0.kind == .modification }
        XCTAssertEqual(mods.count, 1)
        let segments = mods.first?.segments ?? []
        XCTAssertFalse(segments.isEmpty)
        XCTAssertTrue(segments.contains { $0.op == .delete })
        XCTAssertTrue(segments.contains { $0.op == .insert })
        XCTAssertTrue(segments.contains { $0.op == .equal })
    }

    func testParagraphSplitIsLabeledAsBoundary() {
        let report = RiftEngine.compare(
            "The first half continues directly into the second half without a break.\n",
            "The first half continues directly\n\ninto the second half without a break.\n")
        XCTAssertEqual(report.document.hunks.filter { $0.kind == .paragraphBoundary }.count, 1)
        XCTAssertEqual(report.verdict, .changed(contentChanges: 1, formattingOnly: 0))
    }

    func testLadderLevelsAreOrdered() {
        XCTAssertLessThan(StrictnessLevel.exact, StrictnessLevel.encoding)
        XCTAssertLessThan(StrictnessLevel.spacing, StrictnessLevel.layout)
        XCTAssertEqual(StrictnessLevel.layout.label, "L3")
    }
}
