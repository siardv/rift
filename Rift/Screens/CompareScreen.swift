import RiftEngine
import SwiftUI

/// m0 placeholder: wordmark plus an engine wiring check;
/// the real compare screen (sdd §7.2) lands with m2
struct CompareScreen: View {
    // the app renders reports, it never computes (sdd §1.5); this single call
    // proves the RiftEngine package is linked and callable from the app target
    private let engineIsLinked = RiftEngine.compare("rift", "rift").verdict == .identical

    var body: some View {
        VStack(spacing: 12) {
            Text("Rift")
                .font(.system(size: 64, weight: .semibold))
                .fontDesign(.serif)
            Text("See what actually changed.")
                .font(.title3)
                .fontDesign(.serif)
                .foregroundStyle(.secondary)
            Text(engineIsLinked ? "engine linked" : "engine check failed")
                .font(.footnote.monospaced())
                .foregroundStyle(.tertiary)
                .padding(.top, 24)
        }
        .padding()
    }
}

#Preview {
    CompareScreen()
}
