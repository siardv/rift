import UIKit
import XCTest

final class PasteDeliveryTests: XCTestCase {
    @MainActor
    func testAcceptedProviderSurvivesCoordinatorReplacement() async throws {
        var received: [String]?
        var coordinator: PasteControl.Coordinator? = .init { received = $0 }
        weak let originalCoordinator = coordinator
        let provider = NSItemProvider(object: NSString(string: "accepted text"))
        coordinator?.paste(itemProviders: [provider])
        coordinator = nil
        XCTAssertNil(originalCoordinator)

        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while received == nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(received, ["accepted text"])
    }
}
