import SwiftUI
import UIKit

/// the prose reading view (fr-8, sdd §7.4): paragraphs as flowing serif text
/// with inline track-changes-style highlights; unchanged runs collapse to a
/// rule interrupted by "n unchanged paragraphs". side-by-side pairs the two
/// originals in columns; stacked pairs (m3.3a) pair them vertically where two
/// columns do not fit. the presentation enum lives in ResultPresentation.swift.
/// serif here is one of its two production roles (sdd §7.1)
struct ProseDiffView: View {
    let blocks: [ProseBlock]
    let presentation: DiffPresentation
    let changeTotal: Int
    let styler: PieceStyler
    let fontScale: Double

    @State private var expandedBlocks: Set<Int> = []
    @State private var selectedBlockID: Int?
    @ScaledMetric(relativeTo: .body) private var proseUnit: CGFloat = Theme.proseBaseSize

    private var proseFont: Font {
        .system(size: proseUnit * fontScale, design: .serif)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(blocks) { block in
                blockView(block)
                    .id(DiffViewModel.anchorID(block.hunkIndex))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - blocks

    @ViewBuilder
    private func blockView(_ block: ProseBlock) -> some View {
        if block.kind == .equal {
            equalBlock(block)
        } else {
            changeBlock(block)
        }
    }

    @ViewBuilder
    private func equalBlock(_ block: ProseBlock) -> some View {
        let count = max(block.merged.count, max(block.sideA.count, block.sideB.count))
        let collapsed = count > 3 && !expandedBlocks.contains(block.id)
        VStack(alignment: .leading, spacing: 14) {
            if collapsed {
                paragraphContent(block, index: 0)
                expander(blockID: block.id, hiddenCount: count - 2)
                paragraphContent(block, index: count - 1)
            } else {
                ForEach(0..<max(count, 0), id: \.self) { index in
                    paragraphContent(block, index: index)
                }
                if count > 3 {
                    collapser(blockID: block.id)
                }
            }
        }
    }

    /// one paragraph position, honoring the active presentation; unchanged
    /// paragraphs appear once in the stacked-pair reading, like the inline one
    @ViewBuilder
    private func paragraphContent(_ block: ProseBlock, index: Int) -> some View {
        switch presentation {
        case .unified, .stackedPairs:
            if index < block.merged.count {
                paragraphText(block.merged[index])
            }
        case .sideBySide:
            // two gaps flank the separator, matching ColumnFit.columnGap
            HStack(alignment: .top, spacing: 6) {
                sideParagraph(block.sideA, index: index)
                Rectangle().fill(Theme.hairline).frame(width: 0.5)
                sideParagraph(block.sideB, index: index)
            }
        }
    }

    @ViewBuilder
    private func sideParagraph(_ paragraphs: [ProseParagraph], index: Int) -> some View {
        if index < paragraphs.count {
            paragraphText(paragraphs[index])
                .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            Text("—")
                .font(proseFont)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .accessibilityHidden(true)
        }
    }

    private func paragraphText(_ paragraph: ProseParagraph) -> some View {
        Text(styler.attributed(paragraph.pieces))
            .font(proseFont)
            .lineSpacing(3)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func changeBlock(_ block: ProseBlock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if block.kind == .paragraphBoundary {
                Label("paragraph split · merge — wording unchanged", systemImage: "paragraphsign")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            switch presentation {
            case .unified:
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(block.merged) { paragraph in
                        paragraphText(paragraph)
                    }
                }
            case .sideBySide:
                let count = max(block.sideA.count, block.sideB.count)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(0..<max(count, 1), id: \.self) { index in
                        // two gaps flank the separator, matching ColumnFit.columnGap
                        HStack(alignment: .top, spacing: 6) {
                            sideParagraph(block.sideA, index: index)
                            Rectangle().fill(Theme.hairline).frame(width: 0.5)
                            sideParagraph(block.sideB, index: index)
                        }
                    }
                }
            case .stackedPairs:
                stackedPair(block)
            }
            if selectedBlockID == block.id {
                copyActions(block)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedBlockID = selectedBlockID == block.id ? nil : block.id
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Change \(block.ordinal ?? 0) of \(changeTotal): \(block.accessibilitySummary)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Copy before") { copy(plain(block.sideA)) }
        .accessibilityAction(named: "Copy after") { copy(plain(block.sideB)) }
    }

    /// the paired reading where two columns do not fit (m3.3a): the a passage,
    /// a hairline, then the b passage, each behind its side marker; an absent
    /// side is omitted rather than shown as a placeholder
    private func stackedPair(_ block: ProseBlock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !block.sideA.isEmpty {
                stackedSide(block.sideA, marker: "A")
            }
            if !block.sideA.isEmpty, !block.sideB.isEmpty {
                RuleLine()
            }
            if !block.sideB.isEmpty {
                stackedSide(block.sideB, marker: "B")
            }
        }
    }

    /// one side of a stacked pair: the marker in a 20-point leading column,
    /// hidden from voiceover because the block's label already names both sides
    private func stackedSide(_ paragraphs: [ProseParagraph], marker: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(marker)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 20, alignment: .leading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(paragraphs) { paragraph in
                    paragraphText(paragraph)
                }
            }
        }
    }

    /// action row on a tapped change (sdd §7.5): same three outputs as m2
    private func copyActions(_ block: ProseBlock) -> some View {
        CopyActionRow(
            canCopyA: !block.sideA.isEmpty,
            canCopyB: !block.sideB.isEmpty,
            onCopyA: { copy(plain(block.sideA)) },
            onCopyB: { copy(plain(block.sideB)) },
            onCopyBoth: { copy(plain(block.sideA) + "\n⸻\n" + plain(block.sideB)) })
    }

    // MARK: - collapsed context (rule-led, sdd §7.4)

    private func expander(blockID: Int, hiddenCount: Int) -> some View {
        Button {
            expandedBlocks.insert(blockID)
        } label: {
            InterruptedRule(text: "\(hiddenCount) unchanged \(hiddenCount == 1 ? "paragraph" : "paragraphs")")
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show \(hiddenCount) unchanged paragraphs")
    }

    private func collapser(blockID: Int) -> some View {
        Button {
            expandedBlocks.remove(blockID)
        } label: {
            InterruptedRule(text: "collapse unchanged")
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Collapse unchanged paragraphs")
    }

    // MARK: - copy helpers

    private func plain(_ paragraphs: [ProseParagraph]) -> String {
        paragraphs.map { $0.pieces.map(\.text).joined() }.joined(separator: "\n\n")
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        selectedBlockID = nil
    }
}
