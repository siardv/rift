import SwiftUI

/// the existing icon artwork supplies the shape; the interface supplies ink.
/// render a mask so the opaque ivory icon tile never enters the neutral header
struct BrandMark: View {
    var body: some View {
        if let icon = AppIconView.bundledIcon() {
            Theme.ink
                .frame(width: 38, height: 38)
                .mask {
                    Image(uiImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .saturation(0)
                        .contrast(10)
                        .colorInvert()
                        .luminanceToAlpha()
                }
                .accessibilityHidden(true)
        }
    }
}
