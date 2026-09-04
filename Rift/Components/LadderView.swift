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

/// the "show your work" view (sdd §7.2): four rows, one per ladder level —
/// equal or not at that level, and how many sites resolve exactly there
struct LadderView: View {
    let ladder: [LadderLevelResult]

    private var convergence: StrictnessLevel? {
        ladder.first(where: \.isEqual)?.level
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(ladder.enumerated()), id: \.offset) { index, row in
                ladderRow(row)
                if index < ladder.count - 1 {
                    Divider().overlay(Theme.hairline)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func ladderRow(_ row: LadderLevelResult) -> some View {
        let isConvergence = row.level == convergence
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(row.level.label)
                .font(.footnote.weight(.semibold).monospaced())
                .foregroundStyle(isConvergence ? Color.accentColor : Color.secondary)
                .frame(width: 26, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(row.level.displayName)
                        .font(.subheadline.weight(isConvergence ? .semibold : .regular))
                        .fontDesign(.serif)
                    if isConvergence {
                        Text("converges here")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(row.level.ruleSummary)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            if row.resolvedSiteCount > 0 {
                Text("\(row.resolvedSiteCount) set aside")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: row.isEqual ? "checkmark.circle.fill" : "xmark.circle")
                .font(.subheadline)
                .foregroundStyle(row.isEqual ? Color.accentColor : Color.secondary.opacity(0.6))
                .accessibilityLabel(row.isEqual ? "equal at this level" : "still different")
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}
