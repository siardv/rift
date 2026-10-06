import RiftEngine
import XCTest

/// real session regressions for the interval between editing and publication
final class CompareSessionTests: XCTestCase {
    @MainActor
    func testEditInvalidatesResultBeforeDebounceAndExportsCurrentText() async throws {
        let session = CompareSession()
        session.textA = "Before.\n"
        session.textB = "After.\n"
        try await waitForCurrent(session)
        let oldReport = try XCTUnwrap(session.report)

        session.textB = "A much longer replacement.\n"
        XCTAssertFalse(session.isResultCurrent)
        XCTAssertFalse(session.isComparing)
        XCTAssertEqual(session.report, oldReport)
        XCTAssertNil(session.countsB)
        try await waitForCurrent(session)
        let report = try XCTUnwrap(session.report)
        XCTAssertEqual(report, RiftEngine.compare(session.textA, session.textB,
                                                  options: session.currentOptions))
        let summary = Export.summary(report: report, a: session.textA, b: session.textB,
                                     countsA: session.countsA, countsB: session.countsB,
                                     modeChoice: session.modeChoice)
        XCTAssertTrue(summary.contains("A much longer replacement."))
        let patch = Export.unifiedPatch(a: session.textA, b: session.textB,
                                        document: report.document)
        XCTAssertTrue(patch.contains("+A much longer replacement.\n"))
        XCTAssertTrue(patch.contains("-Before.\n"))
    }

    @MainActor
    func testModeRuleAndProfileChangesInvalidateCurrentResult() async throws {
        let session = CompareSession()
        session.textA = "x\n"
        session.textB = "x"
        try await waitForCurrent(session)
        session.customRules.ignoreCase = true
        XCTAssertTrue(session.isResultCurrent, "inactive custom rules do not change Smart")

        session.modeChoice = .strict
        XCTAssertFalse(session.isResultCurrent)
        XCTAssertFalse(session.isComparing)
        try await waitForCurrent(session)
        XCTAssertEqual(session.report, RiftEngine.compare(session.textA, session.textB,
                                                          options: session.currentOptions))

        session.modeChoice = .custom
        XCTAssertFalse(session.isResultCurrent)
        try await waitForCurrent(session)
        session.customRules.stripTrailingWhitespace = false
        XCTAssertFalse(session.isResultCurrent)
        try await waitForCurrent(session)
        session.profileOverride = .plain
        XCTAssertFalse(session.isResultCurrent)
        try await waitForCurrent(session)
        XCTAssertEqual(session.report?.profile.profile, .plain)
        XCTAssertEqual(session.report, RiftEngine.compare(session.textA, session.textB,
                                                          options: session.currentOptions))
    }

    @MainActor
    func testRapidEditsPublishOnlyLatestGenerationAndClearRemovesResult() async throws {
        let session = CompareSession()
        session.textA = "first"
        session.textB = "second"
        try await waitForCurrent(session)
        let publications = session.publishCount
        session.textB = "intermediate"
        session.textB = "final replacement"
        XCTAssertFalse(session.isResultCurrent)
        try await waitForCurrent(session)
        XCTAssertEqual(session.publishCount, publications + 1)
        XCTAssertEqual(session.report, RiftEngine.compare("first", "final replacement"))
        session.clear(.a, undoManager: nil)
        XCTAssertFalse(session.isResultCurrent)
        XCTAssertNil(session.report)
        session.undoClear()
        XCTAssertFalse(session.isResultCurrent)
        try await waitForCurrent(session)
        XCTAssertEqual(session.textA, "first")
        XCTAssertEqual(session.textB, "final replacement")
    }

    @MainActor
    func testNativeClearUndoRestoresOnlyItsSourceAfterOtherPaneEditing() async throws {
        let session = CompareSession()
        let manager = UndoManager()
        manager.groupsByEvent = false
        session.setText("Original text.", for: .a, sourceLabel: "original.txt", decodedAs: nil)
        session.textB = "Revision text."

        manager.beginUndoGrouping()
        session.clear(.a, undoManager: manager)
        manager.endUndoGrouping()
        XCTAssertTrue(manager.canUndo)
        XCTAssertEqual(manager.undoActionName, "Clear")
        XCTAssertEqual(session.undoablePane, .a)
        session.textB = "Edited revision."
        manager.undo()

        // the native callback restores on the main actor asynchronously
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while session.textA.isEmpty && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(session.textA, "Original text.")
        XCTAssertEqual(session.meta(for: .a).sourceLabel, "original.txt")
        XCTAssertEqual(session.textB, "Edited revision.")
        XCTAssertNil(session.undoablePane)
        XCTAssertFalse(manager.canUndo)
    }

    @MainActor
    func testByteDistinctUnicodeEditInvalidatesIdenticalResult() async throws {
        let session = CompareSession()
        session.textA = "é"
        session.textB = "é"
        try await waitForCurrent(session)
        XCTAssertEqual(session.report?.verdict, .identical)
        session.textB = "e\u{301}"
        XCTAssertFalse(session.isResultCurrent)
        try await waitForCurrent(session)
        XCTAssertNotEqual(session.report?.verdict, .identical)
        XCTAssertEqual(session.report, RiftEngine.compare(session.textA, session.textB))
    }

    @MainActor
    private func waitForCurrent(_ session: CompareSession) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while !session.isResultCurrent && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(session.isResultCurrent, "comparison did not publish before deadline")
        XCTAssertFalse(session.isComparing)
    }
}
