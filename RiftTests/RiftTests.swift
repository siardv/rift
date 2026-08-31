import XCTest
import RiftEngine

/// app-side smoke tests; these run on the ios simulator via the Rift scheme,
/// so ci's macos job exercises the engine in its shipping environment
final class RiftTests: XCTestCase {
    func testEngineReachableFromAppTestBundle() {
        XCTAssertEqual(RiftEngine.compare("a", "a").verdict, .identical)
    }
}
