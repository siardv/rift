import SwiftUI

/// shared visual furniture of the m3 rule-led grammar (sdd §7.1): rules in two
/// weights, the interrupted rule that stands in for collapsed context, plain
/// textual actions with full hit areas, and the divided copy row. nothing here
/// draws a shadow, a capsule, or a card

// MARK: - rules

/// a horizontal rule in the two weights the grammar allows: one point for
/// genuine boundaries, a half-point hairline for subdivisions
struct RuleLine: View {
    enum Weight {
        case rule
        case hairline
    }

    var weight: Weight = .hairline

    var body: some View {
        Rectangle()
            .fill(weight == .rule ? Theme.rule : Theme.hairline)
            .frame(height: weight == .rule ? 1 : 0.5)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

/// a horizontal rule interrupted by a mono label — the shared grammar for
/// collapsed unchanged context in both result views (sdd §7.4)
struct InterruptedRule: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            RuleLine()
            Text(text)
                .font(Theme.data)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(1)
            RuleLine()
        }
    }
}

// MARK: - actions

/// a plain textual action in the accent ink with a 44-point hit area — the
/// replacement for m2's bordered capsules on the workspace (nfr-5)
struct TextAction: View {
    let title: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 8)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
    }
}

/// the action row on a tapped change (sdd §7.5): copy a, copy b, copy both —
/// text actions divided by hairlines, bounded by hairlines, no capsules. the
/// copy outputs themselves are owned by the calling view
struct CopyActionRow: View {
    let canCopyA: Bool
    let canCopyB: Bool
    let onCopyA: () -> Void
    let onCopyB: () -> Void
    let onCopyBoth: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            TextAction(title: "Copy A", action: onCopyA)
                .disabled(!canCopyA)
            columnRule
            TextAction(title: "Copy B", action: onCopyB)
                .disabled(!canCopyB)
            columnRule
            TextAction(title: "Copy both", action: onCopyBoth)
            Spacer(minLength: 0)
        }
        .overlay(alignment: .top) { RuleLine() }
        .overlay(alignment: .bottom) { RuleLine() }
    }

    private var columnRule: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: 0.5, height: 18)
            .accessibilityHidden(true)
    }
}
