import SwiftUI
import UIKit

/// which result layout is active (fr-7); defaults per sdd §7.2
enum DiffPresentation: String, Hashable {
    case unified
    case sideBySide
}

/// the prose reading view (fr-8, sdd §7.4): paragraphs as flowing serif text
/// with inline track-changes-style highlights; unchanged runs collapse to a
/// "⋯ n unchanged paragraphs" pill. side-by-side pairs the two originals
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
                expanderPill(blockID: block.id, hiddenCount: count - 2)
                paragraphContent(block, index: count - 1)
            } else {
                ForEach(0..<max(count, 0), id: \.self) { index in
                    paragraphContent(block, index: index)
                }
                if count > 3 {
                    collapsePill(blockID: block.id)
                }
            }
        }
    }

    /// one paragraph position, honoring the active presentation
    @ViewBuilder
    private func paragraphContent(_ block: ProseBlock, index: Int) -> some View {
        switch presentation {
        case .unified:
            if index < block.merged.count {
                paragraphText(block.merged[index])
            }
        case .sideBySide:
            HStack(alignment: .top, spacing: 12) {
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
                .foregroundStyle(.quaternary)
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
                        HStack(alignment: .top, spacing: 12) {
                            sideParagraph(block.sideA, index: index)
                            Rectangle().fill(Theme.hairline).frame(width: 0.5)
                            sideParagraph(block.sideB, index: index)
                        }
                    }
                }
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

    /// action row on a tapped change (sdd §7.5)
    private func copyActions(_ block: ProseBlock) -> some View {
        HStack(spacing: 8) {
            Button("Copy A") { copy(plain(block.sideA)) }
                .disabled(block.sideA.isEmpty)
            Button("Copy B") { copy(plain(block.sideB)) }
                .disabled(block.sideB.isEmpty)
            Button("Copy both") { copy(plain(block.sideA) + "\n⸻\n" + plain(block.sideB)) }
        }
        .font(.caption)
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
    }

    // MARK: - collapse pills

    private func expanderPill(blockID: Int, hiddenCount: Int) -> some View {
        Button {
            expandedBlocks.insert(blockID)
        } label: {
            Text("⋯ \(hiddenCount) unchanged \(hiddenCount == 1 ? "paragraph" : "paragraphs")")
                .font(.caption)
                .fontDesign(.serif)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show \(hiddenCount) unchanged paragraphs")
    }

    private func collapsePill(blockID: Int) -> some View {
        Button {
            expandedBlocks.remove(blockID)
        } label: {
            Text("collapse unchanged")
                .font(.caption2)
                .fontDesign(.serif)
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
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
