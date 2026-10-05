import SwiftUI

/// previous / next with the change label (fr-9, sdd §7.4): a rectangular bar
/// in the bottom safe-area inset, bounded by a one-point rule — no floating
/// capsule, no shadow. 44-point targets (nfr-5). the label and the arrows come
/// from one ChangeSelection, so they never contradict each other (m3.3a):
/// `2 changes` while nothing is selected, `Change 1 of 2` after a selection
struct ChangeNavigator: View {
    let selection: ChangeSelection
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            RuleLine(weight: .rule)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Button(action: onPrevious) {
                    Image(systemName: "chevron.up")
                        .font(.body.weight(.medium))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(!selection.canGoPrevious)
                .accessibilityLabel("Previous change")

                Text(selection.label)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.ink)
                    .frame(minWidth: 96)

                Button(action: onNext) {
                    Image(systemName: "chevron.down")
                        .font(.body.weight(.medium))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(!selection.canGoNext)
                .accessibilityLabel("Next change")
            }
            .padding(.horizontal, 8)
        }
        .background(Theme.paper)
    }
}

#Preview {
    VStack(spacing: 24) {
        ChangeNavigator(selection: ChangeSelection(total: 7), onPrevious: {}, onNext: {})
        ChangeNavigator(selection: ChangeSelection(total: 7, current: 2), onPrevious: {}, onNext: {})
    }
    .tint(Theme.accent)
}
