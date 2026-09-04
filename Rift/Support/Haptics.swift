import UIKit

/// the app's single haptic (sdd §7.1): fired once when a comparison completes
/// with content changes; nothing else vibrates
@MainActor
enum Haptics {
    static func comparisonFoundContentChanges() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
