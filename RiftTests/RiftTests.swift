import XCTest
import RiftEngine

/// app-side smoke tests; these run on the ios simulator via the Rift scheme,
/// so ci's macos job exercises the engine in its shipping environment
final class RiftTests: XCTestCase {
    func testEngineReachableFromAppTestBundle() {
        XCTAssertEqual(RiftEngine.compare("a", "a").verdict, .identical)
    }

    /// m2 addendum (fr-10): formatting-only sites arrive with provenance and
    /// always mirror the verdict's formatting count
    func testFormattingSitesExposedToAppTargets() {
        let report = RiftEngine.compare("x\n", "x")
        guard case .formattingOnly(let level, let count) = report.verdict else {
            return XCTFail("expected formattingOnly, got \(report.verdict)")
        }
        XCTAssertEqual(level, .encoding)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(report.sites.count, 1)
        XCTAssertEqual(report.sites[0].level, .encoding)
        XCTAssertEqual(report.sites[0].rangeA, 1..<2)
        XCTAssertTrue(report.sites[0].rangeB.isEmpty)
    }
}
