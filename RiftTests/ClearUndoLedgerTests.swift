import XCTest

/// m3.1: the pane-local clear / undo ledger (sdd §7.5). the ledger source is
/// compiled into this bundle from Rift/State/ClearUndoLedger.swift (see
/// project.yml), so these run without a host app on the same simulator job
final class ClearUndoLedgerTests: XCTestCase {
    private typealias Ledger = ClearUndoLedger<String, String?>

    func testEmptyClearRecordsNothing() {
        var ledger = Ledger()
        XCTAssertNil(ledger.recordClear(of: "A", text: "", meta: nil))
        XCTAssertNil(ledger.pending)
        XCTAssertNil(ledger.pendingPane)
    }

    func testRecordSetsPendingPaneAndUniqueToken() {
        var ledger = Ledger()
        let first = ledger.recordClear(of: "A", text: "one", meta: "one.txt")
        XCTAssertEqual(ledger.pendingPane, "A")
        XCTAssertEqual(first?.text, "one")
        XCTAssertEqual(first?.meta, "one.txt")
        let second = ledger.recordClear(of: "A", text: "two", meta: nil)
        XCTAssertNotNil(first?.token)
        XCTAssertNotNil(second?.token)
        XCTAssertNotEqual(first?.token, second?.token)
    }

    func testOtherPaneEditsPreserveRecord() {
        var ledger = Ledger()
        let record = ledger.recordClear(of: "A", text: "kept", meta: nil)
        ledger.noteText("typing in b", in: "B")
        ledger.noteText("", in: "B")
        XCTAssertEqual(ledger.pending, record)
        XCTAssertEqual(ledger.pendingPane, "A")
    }

    func testSamePaneNonEmptyInputInvalidates() {
        var ledger = Ledger()
        ledger.recordClear(of: "A", text: "gone", meta: nil)
        ledger.noteText("refilled", in: "A")
        XCTAssertNil(ledger.pending)
        XCTAssertNil(ledger.pendingPane)
    }

    func testEmptyInputDoesNotInvalidate() {
        var ledger = Ledger()
        let record = ledger.recordClear(of: "A", text: "gone", meta: nil)
        // the clear itself writes "" into the pane after recording
        ledger.noteText("", in: "A")
        XCTAssertEqual(ledger.pending, record)
    }

    func testSwapInvalidates() {
        var ledger = Ledger()
        ledger.recordClear(of: "B", text: "gone", meta: nil)
        ledger.noteSwap()
        XCTAssertNil(ledger.pending)
        XCTAssertNil(ledger.pendingPane)
    }

    func testSecondClearSupersedesFirst() {
        var ledger = Ledger()
        let first = ledger.recordClear(of: "A", text: "first", meta: nil)
        let second = ledger.recordClear(of: "B", text: "second", meta: nil)
        XCTAssertEqual(ledger.pending, second)
        XCTAssertEqual(ledger.pendingPane, "B")
        // the superseded record is no longer restorable, and trying leaves the
        // current one untouched
        XCTAssertNil(ledger.takePending(matching: first!))
        XCTAssertEqual(ledger.pending, second)
    }

    func testMismatchedTokenDoesNotConsumeCurrentRecord() {
        var ledger = Ledger()
        let stale = ledger.recordClear(of: "A", text: "old", meta: nil)!
        ledger.noteText("refilled", in: "A")
        // a later clear of the same pane: same pane, different token
        let current = ledger.recordClear(of: "A", text: "new", meta: nil)!
        XCTAssertEqual(stale.pane, current.pane)
        XCTAssertNotEqual(stale.token, current.token)
        XCTAssertNil(ledger.takePending(matching: stale))
        XCTAssertEqual(ledger.pending, current)
        XCTAssertEqual(ledger.takePending(matching: current), current)
        XCTAssertNil(ledger.pending)
    }

    func testTakeIsOneShot() {
        var ledger = Ledger()
        let record = ledger.recordClear(of: "A", text: "once", meta: "a.txt")
        XCTAssertEqual(ledger.takePending(), record)
        XCTAssertNil(ledger.takePending())
        XCTAssertNil(ledger.pending)
        XCTAssertNil(ledger.pendingPane)
        // a matching take after the one-shot take also finds nothing
        XCTAssertNil(ledger.takePending(matching: record!))
    }
}
