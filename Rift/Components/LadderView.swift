import RiftEngine
import SwiftUI

extension StrictnessLevel {
    var displayName: String {
        switch self {
        case .exact: return "Exact"
        case .encoding: return "Encoding"
        case .spacing: return "Spacing"
        case .layout: return "Layout"
        }
    }

    var ruleSummary: String {
        switch self {
        case .exact: return "texts as given"
        case .encoding: return "line endings, NFC, invisibles, trailing space"
        case .spacing: return "space runs, blank lines, NBSP, typography"
        case .layout: return "wrapping (prose) / indentation (code)"
        }
    }
}

/// the "show your work" view (sdd §7.2) as a compact analytical table: one
/// row per ladder level — level, name, `=` / `≠` at that level, and the number
/// of sites resolved exactly there. convergence is marked by weight and a
/// one-point rule above the first equal row, never by helper text; the sites
/// column is explained once by the caller's footer
struct LadderView: View {
    let ladder: [LadderLevelResult]

    private var convergence: StrictnessLevel? {
        ladder.first(where: \.isEqual)?.level
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 0) {
            ForEach(Array(ladder.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    if row.level == convergence {
                        RuleLine(weight: .rule)
                    } else {
                        RuleLine()
                    }
                }
                ladderRow(row)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Strictness ladder")
    }

    /// modifiers sit on the cells, never on the GridRow, so the grid keeps
    /// treating it as a row; voiceover reads the whole row from its first cell
    private func ladderRow(_ row: LadderLevelResult) -> some View {
        let isConvergence = row.level == convergence
        let weight: Font.Weight = isConvergence ? .semibold : .regular
        let hasSites = row.resolvedSiteCount > 0
        return GridRow {
            Text(row.level.label)
                .font(Theme.data.weight(weight))
                .foregroundStyle(isConvergence ? Theme.ink : Color.secondary)
                .padding(.vertical, 9)
                .accessibilityLabel(accessibilityDescription(row, isConvergence: isConvergence))
            Text(row.level.displayName.uppercased())
                .font(Theme.data.weight(weight))
                .foregroundStyle(isConvergence ? Theme.ink : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 9)
                .accessibilityHidden(true)
            Text(row.isEqual ? "=" : "≠")
                .font(Theme.data.weight(.semibold))
                .foregroundStyle(row.isEqual ? Theme.ink : Color.secondary)
                .padding(.vertical, 9)
                .gridColumnAlignment(.center)
                .accessibilityHidden(true)
            Text(hasSites ? "\(row.resolvedSiteCount)" : "—")
                .font(Theme.data.weight(weight))
                .foregroundStyle(hasSites ? Theme.ink : Color.secondary)
                .frame(minWidth: 24, alignment: .trailing)
                .padding(.vertical, 9)
                .gridColumnAlignment(.trailing)
                .accessibilityHidden(true)
        }
    }

    private func accessibilityDescription(_ row: LadderLevelResult, isConvergence: Bool) -> String {
        var text = "\(row.level.label), \(row.level.displayName): "
        text += row.isEqual ? "equal at this level" : "still different"
        if isConvergence {
            text += ", converges here"
        }
        if row.resolvedSiteCount > 0 {
            text += ", \(row.resolvedSiteCount) \(row.resolvedSiteCount == 1 ? "site" : "sites") resolved at this level"
        }
        return text
    }
}

#Preview {
    LadderView(ladder: [
        LadderLevelResult(level: .exact, isEqual: false, resolvedSiteCount: 0),
        LadderLevelResult(level: .encoding, isEqual: false, resolvedSiteCount: 2),
        LadderLevelResult(level: .spacing, isEqual: true, resolvedSiteCount: 3),
        LadderLevelResult(level: .layout, isEqual: true, resolvedSiteCount: 0),
    ])
    .padding()
}
