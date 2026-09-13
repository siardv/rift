import SwiftUI

/// previous / next with the `n / k` counter (fr-9, sdd §7.4): a rectangular bar
/// in the bottom safe-area inset, bounded by a one-point rule — no floating
/// capsule, no shadow. 44-point targets (nfr-5)
struct ChangeNavigator: View {
    let total: Int
    let current: Int
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            RuleLine(weight: .rule)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Button(action: onPrevious) {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.medium))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(current <= 1)
                .accessibilityLabel("Previous change")

                Text("\(max(current, 1)) / \(total)")
                    .font(.footnote.monospaced())
                    .foregroundStyle(Theme.ink)
                    .frame(minWidth: 56)
                    .accessibilityLabel("Change \(max(current, 1)) of \(total)")

                Button(action: onNext) {
                    Image(systemName: "arrow.down")
                        .font(.body.weight(.medium))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(current >= total)
                .accessibilityLabel("Next change")
            }
            .padding(.horizontal, 8)
        }
        .background(Theme.paper)
    }
}

#Preview {
    ChangeNavigator(total: 7, current: 2, onPrevious: {}, onNext: {})
        .tint(Theme.accent)
}
