import XCTest

/// m3.3a: the pure result-presentation state (layout choice, column rule,
/// change selection). the source is compiled into this bundle from
/// Rift/State/ResultPresentation.swift (see project.yml), so these run
/// without a host app on the same simulator job
final class ResultPresentationTests: XCTestCase {
    // MARK: - layout choice

    func testResolverTable() {
        XCTAssertEqual(LayoutChoice.automatic.resolvePresentation(twoColumnsFit: true), .sideBySide)
        XCTAssertEqual(LayoutChoice.automatic.resolvePresentation(twoColumnsFit: false), .unified)
        XCTAssertEqual(LayoutChoice.inline.resolvePresentation(twoColumnsFit: true), .unified)
        XCTAssertEqual(LayoutChoice.inline.resolvePresentation(twoColumnsFit: false), .unified)
        XCTAssertEqual(LayoutChoice.paired.resolvePresentation(twoColumnsFit: true), .sideBySide)
        XCTAssertEqual(LayoutChoice.paired.resolvePresentation(twoColumnsFit: false), .stackedPairs)
    }

    func testExplicitChoicesNeverFallBackToTheOtherReading() {
        // an explicit paired choice is paired at every width, an explicit
        // inline choice is inline at every width
        for fits in [true, false] {
            XCTAssertNotEqual(LayoutChoice.paired.resolvePresentation(twoColumnsFit: fits), .unified)
            XCTAssertEqual(LayoutChoice.inline.resolvePresentation(twoColumnsFit: fits), .unified)
        }
    }

    func testTitlesAndDescriptions() {
        XCTAssertEqual(LayoutChoice.allCases.map(\.menuTitle), ["Automatic", "Inline", "Paired"])
        XCTAssertEqual(LayoutChoice.automatic.menuDescription, "Chooses the best layout for this screen.")
        XCTAssertEqual(LayoutChoice.inline.menuDescription, "Shows changes in one reading flow.")
        XCTAssertEqual(LayoutChoice.paired.menuDescription, "Keeps original and revision separate.")
    }

    func testAccessibilityValues() {
        XCTAssertEqual(LayoutChoice.automatic.accessibilityValue(effective: .unified), "automatic, currently inline")
        XCTAssertEqual(LayoutChoice.automatic.accessibilityValue(effective: .sideBySide), "automatic, currently paired")
        XCTAssertEqual(LayoutChoice.inline.accessibilityValue(effective: .unified), "inline")
        XCTAssertEqual(LayoutChoice.paired.accessibilityValue(effective: .stackedPairs), "paired, stacked")
        XCTAssertEqual(LayoutChoice.paired.accessibilityValue(effective: .sideBySide), "paired, columns")
    }

    // MARK: - column rule

    func testTwoColumnsFitAtDeviceWidthsAndDefaultType() {
        // content widths: iphone portrait, iphone 16 landscape, ipad portrait,
        // ipad split view one half, ipad split view one third
        XCTAssertFalse(ColumnFit.twoColumnsFit(contentWidth: 361, typeScale: 1))
        XCTAssertTrue(ColumnFit.twoColumnsFit(contentWidth: 702, typeScale: 1))
        XCTAssertTrue(ColumnFit.twoColumnsFit(contentWidth: 788, typeScale: 1))
        XCTAssertFalse(ColumnFit.twoColumnsFit(contentWidth: 475, typeScale: 1))
        XCTAssertFalse(ColumnFit.twoColumnsFit(contentWidth: 288, typeScale: 1))
    }

    func testTwoColumnsNeverFitAtAccessibilityType() {
        for width in [361.0, 702, 788, 475, 288] {
            XCTAssertFalse(ColumnFit.twoColumnsFit(contentWidth: width, typeScale: 1.65), "ax1 at \(width)")
            XCTAssertFalse(ColumnFit.twoColumnsFit(contentWidth: width, typeScale: 2.35), "ax3 at \(width)")
        }
        // the ax1 threshold is 320 × 1.65 per column: 1,068.5 points of content
        XCTAssertFalse(ColumnFit.twoColumnsFit(contentWidth: 1068, typeScale: 1.65))
        XCTAssertTrue(ColumnFit.twoColumnsFit(contentWidth: 1069, typeScale: 1.65))
    }

    func testThresholdAtDefaultType() {
        // (652.5 − 12.5) / 2 = 320 exactly
        XCTAssertFalse(ColumnFit.twoColumnsFit(contentWidth: 652, typeScale: 1))
        XCTAssertTrue(ColumnFit.twoColumnsFit(contentWidth: 652.5, typeScale: 1))
        XCTAssertTrue(ColumnFit.twoColumnsFit(contentWidth: 653, typeScale: 1))
    }

    func testReducedViewerScaleKeepsThePhysicalMinimum() {
        // viewer scale 0.8 must not lower the 320-point minimum
        XCTAssertFalse(ColumnFit.twoColumnsFit(contentWidth: 652, typeScale: 0.8))
        XCTAssertTrue(ColumnFit.twoColumnsFit(contentWidth: 652.5, typeScale: 0.8))
        XCTAssertTrue(ColumnFit.twoColumnsFit(contentWidth: 653, typeScale: 0.8))
        XCTAssertFalse(ColumnFit.twoColumnsFit(contentWidth: 361, typeScale: 0.8))
        XCTAssertTrue(ColumnFit.twoColumnsFit(contentWidth: 702, typeScale: 0.8))
    }

    func testEnlargedViewerScaleRaisesTheThreshold() {
        // viewer scale 1.4: 320 × 1.4 = 448 per column, 908.5 points of content
        XCTAssertFalse(ColumnFit.twoColumnsFit(contentWidth: 908, typeScale: 1.4))
        XCTAssertTrue(ColumnFit.twoColumnsFit(contentWidth: 908.5, typeScale: 1.4))
        XCTAssertTrue(ColumnFit.twoColumnsFit(contentWidth: 909, typeScale: 1.4))
        XCTAssertFalse(ColumnFit.twoColumnsFit(contentWidth: 702, typeScale: 1.4))
        XCTAssertFalse(ColumnFit.twoColumnsFit(contentWidth: 788, typeScale: 1.4))
    }

    // MARK: - change selection

    func testInitialStateForSeveralTotals() {
        let none = ChangeSelection(total: 0)
        XCTAssertFalse(none.isVisible)
        XCTAssertEqual(none.label, "0 changes")
        XCTAssertFalse(none.canGoPrevious)
        XCTAssertFalse(none.canGoNext)

        let one = ChangeSelection(total: 1)
        XCTAssertFalse(one.isVisible)
        XCTAssertEqual(one.label, "1 change")
        XCTAssertFalse(one.canGoPrevious)
        XCTAssertTrue(one.canGoNext)

        let two = ChangeSelection(total: 2)
        XCTAssertTrue(two.isVisible)
        XCTAssertEqual(two.label, "2 changes")
        XCTAssertNil(two.current)
        XCTAssertFalse(two.canGoPrevious)
        XCTAssertTrue(two.canGoNext)

        let seven = ChangeSelection(total: 7)
        XCTAssertTrue(seven.isVisible)
        XCTAssertEqual(seven.label, "7 changes")
    }

    func testLabelNeverContradictsTheArrows() {
        var selection = ChangeSelection(total: 2)
        // nothing selected: the label counts, previous is disabled, next is enabled
        XCTAssertEqual(selection.label, "2 changes")
        XCTAssertFalse(selection.canGoPrevious)
        XCTAssertTrue(selection.canGoNext)
        // next from none selects the first change
        XCTAssertEqual(selection.next(), 1)
        XCTAssertEqual(selection.label, "Change 1 of 2")
        XCTAssertFalse(selection.canGoPrevious)
        XCTAssertTrue(selection.canGoNext)
        // the last change disables next
        XCTAssertEqual(selection.next(), 2)
        XCTAssertEqual(selection.label, "Change 2 of 2")
        XCTAssertTrue(selection.canGoPrevious)
        XCTAssertFalse(selection.canGoNext)
        XCTAssertNil(selection.next())
        XCTAssertEqual(selection.current, 2)
    }

    func testPreviousStopsAtTheFirstChange() {
        var selection = ChangeSelection(total: 3, current: 2)
        XCTAssertEqual(selection.previous(), 1)
        XCTAssertFalse(selection.canGoPrevious)
        XCTAssertNil(selection.previous())
        XCTAssertEqual(selection.current, 1)
    }

    func testJumpSelectsOnlyExistingOrdinals() {
        var selection = ChangeSelection(total: 2)
        XCTAssertTrue(selection.jump(to: 1))
        XCTAssertEqual(selection.current, 1)
        XCTAssertFalse(selection.jump(to: 3))
        XCTAssertFalse(selection.jump(to: 0))
        XCTAssertEqual(selection.current, 1)
        XCTAssertNil(ChangeSelection(total: 2, current: 5).current)
    }

    func testRecomputationClampsInsteadOfResetting() {
        var selection = ChangeSelection(total: 3, current: 3)
        selection.clamp(total: 3)
        XCTAssertEqual(selection.current, 3)
        selection.clamp(total: 2)
        XCTAssertEqual(selection.current, 2)
        XCTAssertEqual(selection.label, "Change 2 of 2")
        selection.clamp(total: 1)
        XCTAssertEqual(selection.current, 1)
        XCTAssertFalse(selection.isVisible)
        selection.clamp(total: 0)
        XCTAssertNil(selection.current)
        XCTAssertFalse(selection.isVisible)
    }

    func testClampWithNothingSelectedKeepsNothingSelected() {
        var selection = ChangeSelection(total: 1)
        selection.clamp(total: 4)
        XCTAssertNil(selection.current)
        XCTAssertTrue(selection.isVisible)
        XCTAssertEqual(selection.label, "4 changes")
    }

    func testResetClearsEverything() {
        var selection = ChangeSelection(total: 4, current: 2)
        selection.reset()
        XCTAssertEqual(selection, ChangeSelection())
        XCTAssertFalse(selection.isVisible)
        XCTAssertNil(selection.current)
    }
}
