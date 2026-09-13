import SwiftUI

/// shared visual furniture (sdd §7.1): rules in two weights, the interrupted
/// rule that stands in for collapsed context, plain textual actions with
/// genuine 44-point frames, the one outlined action, the field-row divider,
/// and the divided copy row. nothing here draws a shadow, a capsule, a pill,
/// or a card

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

/// a plain textual action whose label is laid out in a genuine 44-point
/// frame — the replacement for m2's bordered capsules on the workspace
/// (nfr-5). the defaults are the copy row's footnote-medium accent text; the
/// input fields pass their own font, color, padding and alignment (m3.1)
struct TextAction: View {
    let title: String
    var font: Font = .footnote.weight(.medium)
    var color: Color = Theme.accent
    var horizontalPadding: CGFloat = 8
    var alignment: Alignment = .center
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(font)
                .padding(.horizontal, horizontalPadding)
                .frame(minWidth: 44, minHeight: 44, alignment: alignment)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? AnyShapeStyle(color) : AnyShapeStyle(.secondary))
    }
}

/// a plain textual action with a crisp one-point outline (m3.1): the single
/// outlined control in the app, used for `Load sample` beneath the
/// empty-result instruction. the outline is drawn on the padded label; the
/// button itself is laid out at 44 points
struct OutlinedTextAction: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                        .strokeBorder(Theme.fieldEdge, lineWidth: 1)
                )
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.ink)
    }
}

/// the vertical divider of a field's action row: one point of field edge,
/// the height of a line of subheadline text (m3.1)
struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.fieldEdge)
            .frame(width: 1, height: 18)
            .accessibilityHidden(true)
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
