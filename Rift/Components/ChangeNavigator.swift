import SwiftUI

/// floating previous/next chevrons with the "n of k" counter (fr-9, sdd §7.4);
/// bottom-trailing, 44 pt targets (nfr-5)
struct ChangeNavigator: View {
    let total: Int
    let current: Int
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.up")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(current <= 1)
            .accessibilityLabel("Previous change")

            Text("\(max(current, 1)) of \(total)")
                .font(.footnote.monospacedDigit())
                .fontDesign(.serif)
                .foregroundStyle(.secondary)
                .frame(minWidth: 52)
                .accessibilityLabel("Change \(max(current, 1)) of \(total)")

            Button(action: onNext) {
                Image(systemName: "chevron.down")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(current >= total)
            .accessibilityLabel("Next change")
        }
        .tint(.primary)
        .background(
            Capsule()
                .fill(Theme.card)
                .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.10), radius: 8, y: 2)
        )
        .padding(.trailing, 16)
        .padding(.bottom, 16)
    }
}

#Preview {
    ChangeNavigator(total: 7, current: 2, onPrevious: {}, onNext: {})
}
