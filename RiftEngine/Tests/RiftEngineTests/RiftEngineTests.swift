import XCTest
@testable import RiftEngine

final class RiftEngineTests: XCTestCase {
    func testIdenticalInputsReportIdentical() {
        let report = RiftEngine.compare("The quick brown fox.", "The quick brown fox.")
        XCTAssertEqual(report.verdict, .identical)
        XCTAssertEqual(report.ladder.first?.isEqual, true)
    }

    func testDifferingInputsDoNotReportIdentical() {
        let report = RiftEngine.compare("colour", "color")
        XCTAssertNotEqual(report.verdict, .identical)
    }

    func testL0IsByteStrict() {
        // precomposed "é" vs "e" + combining acute: canonically equivalent strings,
        // but L0 is byte-exact (sdd §3.4); these become equal only at L1 (nfc), which lands with m1
        let precomposed = "caf\u{E9}"
        let decomposed = "cafe\u{301}"
        XCTAssertNotEqual(RiftEngine.compare(precomposed, decomposed).verdict, .identical)
    }

    func testProfileOverrideIsRespected() {
        let report = RiftEngine.compare("a", "a", options: .init(profileOverride: .code))
        XCTAssertEqual(report.profile.profile, .code)
        XCTAssertFalse(report.profile.isAutomatic)
    }
}
