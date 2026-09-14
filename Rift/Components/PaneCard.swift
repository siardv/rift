import Foundation
import RiftEngine
import SwiftUI
import UniformTypeIdentifiers

/// one input pane as an editorial input field (fr-1, sdd §7.2, m3.1–m3.2): a
/// white field on the paper canvas with a crisp low-contrast edge, a two-role
/// heading, a pane-specific placeholder or a two-line excerpt, and a 44-point
/// row of plain text actions — tap to edit, drag & drop target. the type keeps
/// its m2 name; only the presentation changed
struct PaneCard: View {
    let pane: PaneID
    @Bindable var session: CompareSession
    let onRequestImport: (PaneID) -> Void

    @State private var isEditorPresented = false
    @State private var isDropTargeted = false
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var text: String {
        session.text(for: pane)
    }

    private var meta: PaneMeta {
        session.meta(for: pane)
    }

    private var word: String {
        pane == .a ? "Original" : "Revision"
    }

    /// the first lines as a flowing excerpt (m3.2): line breaks and runs of
    /// blank lines collapse, so two preview lines carry as much text as they can
    private var excerpt: String {
        text.prefix(240)
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading
                .padding(.horizontal, Theme.fieldInset)
                .accessibilityHidden(true)
            preview
                .padding(.horizontal, Theme.fieldInset)
                .padding(.top, 8)
            actionRow
                .padding(.trailing, Theme.fieldInset)
                .padding(.top, 2)
        }
        // the 44-point action row carries its own slack below its text, so the
        // bottom inset is small to keep the field visually balanced
        .padding(.top, 12)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                .fill(Theme.field)
        )
        .overlay(
            // the crisp edge; the drop target firms it up to ink, nothing filled
            RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                .strokeBorder(isDropTargeted ? Theme.ink : Theme.fieldEdge, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            isEditorPresented = true
        }
        .onDrop(of: [.fileURL, .plainText], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .sheet(isPresented: $isEditorPresented) {
            PaneEditorSheet(pane: pane, session: session)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: - heading: identity line, then one quiet meta line

    /// the identity (`A` + `Original`) on its own line; beneath it, when there
    /// is anything to say, one sans meta line: source, counts, decoded badge.
    /// the meta line has two candidates (one line; source and counts on
    /// separate lines) and accessibility sizes stack outright (m3.2)
    @ViewBuilder
    private var heading: some View {
        VStack(alignment: .leading, spacing: 3) {
            identity
            if hasMeta {
                if dynamicTypeSize.isAccessibilitySize {
                    metaStacked
                } else {
                    ViewThatFits(in: .horizontal) {
                        metaOneLine
                        metaStacked
                    }
                }
            }
        }
    }

    private var hasMeta: Bool {
        meta.sourceLabel != nil || meta.decodedAs != nil || session.counts(for: pane) != nil
    }

    /// the two typographic roles: a compact strong marker and the quiet word
    private var identity: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(pane.rawValue)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text(word)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
        }
        .fixedSize()
    }

    private var metaOneLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            sourceText
            if meta.sourceLabel != nil, session.counts(for: pane) != nil {
                Text("·")
            }
            countsText
            decodedBadge
        }
        .font(.footnote)
        .foregroundStyle(Theme.inkSecondary)
    }

    private var metaStacked: some View {
        VStack(alignment: .leading, spacing: 3) {
            sourceText
            countsText
            decodedBadge
        }
        .font(.footnote)
        .foregroundStyle(Theme.inkSecondary)
    }

    /// filename or source hint; yields first when the line is tight
    @ViewBuilder
    private var sourceText: some View {
        if let source = meta.sourceLabel {
            Text(source)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(-1)
        }
    }

    /// analytical metadata keeps its mono badge (sdd §6.1) and never truncates
    @ViewBuilder
    private var decodedBadge: some View {
        if let decoded = meta.decodedAs {
            Text("DECODED AS \(decoded.uppercased())")
                .font(Theme.dataSmall)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 0.5)
                )
                .fixedSize()
        }
    }

    /// counts in plain words on the field (m3.2); the mono uppercase register
    /// stays with the analytical result metadata and the ladder
    @ViewBuilder
    private var countsText: some View {
        if let counts = session.counts(for: pane) {
            Text(Self.countsPhrase(counts))
                .lineLimit(2)
        }
    }

    private static func countsPhrase(_ counts: TextCounts) -> String {
        func unit(_ n: Int, _ singular: String, _ plural: String) -> String {
            "\(n.formatted()) \(n == 1 ? singular : plural)"
        }
        return unit(counts.characters, "character", "characters")
            + " · " + unit(counts.words, "word", "words")
            + " · " + unit(counts.lines, "line", "lines")
    }

    // MARK: - preview: pane-specific placeholder, or the excerpt

    /// body size, like a text field's own content (m3.2); the field grows to
    /// two lines once there is text and is never squeezed by the result view
    @ViewBuilder
    private var preview: some View {
        if text.isEmpty {
            Text(pane == .a ? "Tap to add original." : "Tap to add revision.")
                .font(.body)
                .foregroundStyle(Theme.inkSecondary)
        } else {
            Text(excerpt)
                .font(.body)
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - action row: Paste | Open File… … Clear / Undo

    /// one row when it fits, otherwise stacked; accessibility sizes stack
    /// outright. order is always Paste → Open File… → Clear / Undo
    @ViewBuilder
    private var actionRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            actionsStacked
        } else {
            ViewThatFits(in: .horizontal) {
                actionsOneRow
                actionsStacked
            }
        }
    }

    /// the row starts `fieldInset - pasteControlPadding` in, so the Paste
    /// label lands on the content's left edge without negative padding
    private var rowLeadingInset: CGFloat {
        max(0, Theme.fieldInset - Theme.pasteControlPadding)
    }

    private var actionsOneRow: some View {
        HStack(alignment: .center, spacing: 0) {
            pasteControl
            RowDivider(height: 20)
            openFileAction
                .padding(.leading, 12)
            Spacer(minLength: 12)
            trailingAction(alignment: .trailing)
        }
        .padding(.leading, rowLeadingInset)
        .frame(minHeight: 44)
    }

    private var actionsStacked: some View {
        VStack(alignment: .leading, spacing: 0) {
            pasteControl
                .padding(.leading, rowLeadingInset)
            openFileAction
                .padding(.leading, Theme.fieldInset)
            trailingAction(alignment: .leading)
                .padding(.leading, Theme.fieldInset)
        }
    }

    /// the system paste control as plain text (fr-1, m3.2): a UIPasteControl
    /// with a clear background and the ink as label, at least 44 points tall
    /// by its own sizing; pasteboard access stays the system's
    private var pasteControl: some View {
        PasteControl { strings in
            session.pasted(strings, into: pane)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var openFileAction: some View {
        TextAction(title: "Open File…", font: .body, color: Theme.ink,
                   horizontalPadding: 0, alignment: .leading) {
            onRequestImport(pane)
        }
        .accessibilityLabel("Open a file")
    }

    /// trailing and subordinate: Clear while the pane has text; Undo, in the
    /// same slot, only while this pane holds the one valid pending clear
    @ViewBuilder
    private func trailingAction(alignment: Alignment) -> some View {
        if text.isEmpty {
            if session.undoablePane == pane {
                TextAction(title: "Undo", font: .body, color: Theme.ink,
                           horizontalPadding: 0, alignment: alignment) {
                    session.undoClear()
                }
                .accessibilityLabel("Undo clear of pane \(pane.rawValue)")
            }
        } else {
            TextAction(title: "Clear", font: .body, color: Theme.inkSecondary,
                       horizontalPadding: 0, alignment: alignment) {
                session.clear(pane, undoManager: undoManager)
            }
            .accessibilityLabel("Clear pane \(pane.rawValue)")
        }
    }

    // MARK: - accessibility

    private var accessibilitySummary: String {
        let role = pane == .a ? "original" : "revision"
        let source = meta.sourceLabel.map { ", \($0)" } ?? ""
        let decoded = meta.decodedAs.map { ", decoded as \($0)" } ?? ""
        if text.isEmpty {
            return "Pane \(pane.rawValue), \(role), empty. Double-tap to type."
        }
        let counts = session.counts(for: pane)
        let detail = counts.map { ", \($0.characters) characters, \($0.words) words, \($0.lines) lines" } ?? ""
        return "Pane \(pane.rawValue), \(role)\(source)\(detail)\(decoded). Double-tap to edit."
    }

    // MARK: - drag & drop (fr-1)

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let session = self.session
        let pane = self.pane
        if let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url = (item as? URL)
                    ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                guard let url else { return }
                let access = url.startAccessingSecurityScopedResource()
                let data = try? Data(contentsOf: url)
                if access { url.stopAccessingSecurityScopedResource() }
                guard let data else { return }
                let name = url.lastPathComponent
                Task { @MainActor in
                    session.ingest(data: data, filename: name, into: pane)
                }
            }
            return true
        }
        if let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) {
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let ns = object as? NSString else { return }
                let text = ns as String
                Task { @MainActor in
                    session.setText(text, for: pane, sourceLabel: nil, decodedAs: nil)
                }
            }
            return true
        }
        return false
    }
}

/// full-screen editor reached by tapping a pane (fr-1: direct typing);
/// autocorrection off — diff inputs must arrive verbatim
struct PaneEditorSheet: View {
    let pane: PaneID
    @Bindable var session: CompareSession
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            TextEditor(text: pane == .a ? $session.textA : $session.textB)
                .font(.body)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($isFocused)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 8)
                .background(Theme.paper)
                .navigationTitle(pane == .a ? "Original" : "Revision")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .tint(Theme.accent)
        .onAppear { isFocused = true }
    }
}
