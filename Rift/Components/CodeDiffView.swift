import SwiftUI
import UIKit

/// the line grid (sdd §7.4): dual line-number gutters, +/− glyphs, intra-line
/// highlights from segments, unchanged runs collapsible with 3 lines of
/// context. side-by-side pairs rows on one shared vertical scroll, so the two
/// columns stay synchronized by construction (fr-7)
struct CodeDiffView: View {
    let rows: [LineRow]
    let pairs: [LinePair]
    let presentation: DiffPresentation
    let changeTotal: Int
    let styler: PieceStyler
    let fontScale: Double
    let useMonospaced: Bool

    @State private var expandedRuns: Set<Int> = []
    @State private var selectedHunk: Int?
    @ScaledMetric(relativeTo: .body) private var codeUnit: CGFloat = Theme.codeBaseSize
    @ScaledMetric(relativeTo: .body) private var gutterWidth: CGFloat = 32

    private var codeFont: Font {
        useMonospaced
            ? .system(size: codeUnit * fontScale, design: .monospaced)
            : .system(size: codeUnit * fontScale)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            switch presentation {
            case .unified:
                ForEach(unifiedItems()) { item in
                    itemView(item)
                }
            case .sideBySide:
                ForEach(pairItems()) { item in
                    itemView(item)
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - display items (collapse logic, sdd §7.4: 3 lines of context)

    private enum DisplayItem: Identifiable {
        case row(LineRow)
        case pair(LinePair)
        case expander(first: Int, count: Int)
        case actions(hunkIndex: Int)

        var id: String {
            switch self {
            case .row(let row): return "r\(row.id)"
            case .pair(let pair): return "p\(pair.id)"
            case .expander(let first, _): return "e\(first)"
            case .actions(let hunkIndex): return "a\(hunkIndex)"
            }
        }
    }

    private func unifiedItems() -> [DisplayItem] {
        var out: [DisplayItem] = []
        var run: [LineRow] = []
        func flushRun() {
            defer { run.removeAll() }
            guard !run.isEmpty else { return }
            let first = run[0].id
            if run.count > 7, !expandedRuns.contains(first) {
                for row in run.prefix(3) { out.append(.row(row)) }
                out.append(.expander(first: first, count: run.count - 6))
                for row in run.suffix(3) { out.append(.row(row)) }
            } else {
                for row in run { out.append(.row(row)) }
            }
        }
        for row in rows {
            if row.kind == .context {
                run.append(row)
            } else {
                flushRun()
                out.append(.row(row))
            }
        }
        flushRun()
        if let selected = selectedHunk,
           let lastIndex = out.lastIndex(where: {
               if case .row(let row) = $0 { return row.hunkIndex == selected && row.kind != .context }
               return false
           }) {
            out.insert(.actions(hunkIndex: selected), at: lastIndex + 1)
        }
        return out
    }

    private func pairItems() -> [DisplayItem] {
        var out: [DisplayItem] = []
        var run: [LinePair] = []
        func flushRun() {
            defer { run.removeAll() }
            guard !run.isEmpty else { return }
            let first = run[0].left?.id ?? run[0].id
            if run.count > 7, !expandedRuns.contains(first) {
                for pair in run.prefix(3) { out.append(.pair(pair)) }
                out.append(.expander(first: first, count: run.count - 6))
                for pair in run.suffix(3) { out.append(.pair(pair)) }
            } else {
                for pair in run { out.append(.pair(pair)) }
            }
        }
        for pair in pairs {
            if pair.left?.kind == .context {
                run.append(pair)
            } else {
                flushRun()
                out.append(.pair(pair))
            }
        }
        flushRun()
        if let selected = selectedHunk,
           let lastIndex = out.lastIndex(where: {
               if case .pair(let pair) = $0 {
                   let row = pair.left ?? pair.right
                   return row?.hunkIndex == selected && row?.kind != .context
               }
               return false
           }) {
            out.insert(.actions(hunkIndex: selected), at: lastIndex + 1)
        }
        return out
    }

    @ViewBuilder
    private func itemView(_ item: DisplayItem) -> some View {
        switch item {
        case .row(let row):
            rowView(row)
                .id(row.isHunkStart ? DiffViewModel.anchorID(row.hunkIndex) : "row-\(row.id)")
        case .pair(let pair):
            pairView(pair)
                .id(pairAnchor(pair))
        case .expander(let first, let count):
            expanderView(first: first, count: count)
        case .actions(let hunkIndex):
            copyActions(hunkIndex: hunkIndex)
        }
    }

    private func pairAnchor(_ pair: LinePair) -> String {
        let row = pair.left ?? pair.right
        if let row, row.isHunkStart || (pair.right?.isHunkStart ?? false) {
            return DiffViewModel.anchorID(row.hunkIndex)
        }
        return "pair-\(pair.id)"
    }

    // MARK: - unified row

    private func rowView(_ row: LineRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            gutter(row.numA)
            gutter(row.numB)
            glyphView(row.kind)
            Text(styler.attributed(row.pieces))
                .font(codeFont)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1.5)
        .background(rowWash(row.kind))
        .contentShape(Rectangle())
        .onTapGesture {
            guard row.kind != .context else { return }
            selectedHunk = selectedHunk == row.hunkIndex ? nil : row.hunkIndex
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowAccessibility(row))
    }

    // MARK: - side-by-side pair row

    private func pairView(_ pair: LinePair) -> some View {
        HStack(alignment: .top, spacing: 0) {
            cellView(pair.left, side: .a)
            Rectangle().fill(Theme.hairline).frame(width: 0.5)
            cellView(pair.right, side: .b)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard let row = pair.left ?? pair.right, row.kind != .context else { return }
            selectedHunk = selectedHunk == row.hunkIndex ? nil : row.hunkIndex
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func cellView(_ row: LineRow?, side: PaneID) -> some View {
        if let row {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                gutter(side == .a ? row.numA : row.numB)
                glyphView(side == .a ? (row.kind == .context ? .context : .delete)
                                     : (row.kind == .context ? .context : .insert))
                Text(styler.attributed(side == .a ? (row.altPieces ?? row.pieces) : row.pieces))
                    .font(codeFont)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(rowWash(row.kind))
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 18)
                .background(Theme.card.opacity(0.45))
        }
    }

    // MARK: - shared row furniture

    private func gutter(_ number: Int?) -> some View {
        Text(number.map(String.init) ?? "")
            .font(.system(size: codeUnit * fontScale * 0.85, design: .monospaced))
            .foregroundStyle(.tertiary)
            .frame(width: gutterWidth, alignment: .trailing)
            .accessibilityHidden(true)
    }

    private func glyphView(_ kind: LineRowKind) -> some View {
        Text(glyph(kind))
            .font(codeFont.weight(.semibold))
            .foregroundStyle(glyphColor(kind))
            .frame(width: 12)
            .accessibilityHidden(true)
    }

    private func glyph(_ kind: LineRowKind) -> String {
        switch kind {
        case .context: return " "
        case .delete: return "−"
        case .insert: return "+"
        }
    }

    private func glyphColor(_ kind: LineRowKind) -> Color {
        switch kind {
        case .context: return .secondary
        case .delete: return Theme.deleteInk(accessible: styler.accessiblePalette)
        case .insert: return Theme.insertInk(accessible: styler.accessiblePalette)
        }
    }

    private func rowWash(_ kind: LineRowKind) -> Color {
        switch kind {
        case .context: return .clear
        case .delete: return Theme.deleteWash(accessible: styler.accessiblePalette).opacity(0.5)
        case .insert: return Theme.insertWash(accessible: styler.accessiblePalette).opacity(0.5)
        }
    }

    private func rowAccessibility(_ row: LineRow) -> String {
        if let label = row.accessibilityLabel {
            return label
        }
        let number = row.numB ?? row.numA ?? 0
        return "line \(number): \(row.pieces.map(\.text).joined())"
    }

    private func expanderView(first: Int, count: Int) -> some View {
        Button {
            expandedRuns.insert(first)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "ellipsis")
                Text("\(count) unchanged \(count == 1 ? "line" : "lines")")
                    .fontDesign(.serif)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Theme.card.opacity(0.6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show \(count) unchanged lines")
    }

    /// action row on a tapped change (sdd §7.5)
    private func copyActions(hunkIndex: Int) -> some View {
        HStack(spacing: 8) {
            Button("Copy A") { copy(hunkText(hunkIndex, side: .a)) }
            Button("Copy B") { copy(hunkText(hunkIndex, side: .b)) }
            Button("Copy both") {
                copy(hunkText(hunkIndex, side: .a) + "\n⸻\n" + hunkText(hunkIndex, side: .b))
            }
        }
        .font(.caption)
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func hunkText(_ hunkIndex: Int, side: PaneID) -> String {
        rows.filter { $0.hunkIndex == hunkIndex }
            .compactMap { row -> String? in
                switch side {
                case .a:
                    guard row.kind != .insert else { return nil }
                    return (row.altPieces ?? row.pieces).map(\.text).joined()
                case .b:
                    guard row.kind != .delete else { return nil }
                    return row.pieces.map(\.text).joined()
                }
            }
            .joined(separator: "\n")
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        selectedHunk = nil
    }
}
