import Foundation
import RiftEngine
import SwiftUI
import UniformTypeIdentifiers

/// one input pane as an editorial input field (fr-1, sdd §7.2, m3.1): a paper
/// field on the ivory canvas with a crisp low-contrast edge, a two-role
/// heading, a pane-specific placeholder or the first lines, and a 44-point row
/// of plain text actions — tap to edit, drag & drop target. the type keeps its
/// m2 name; only the presentation changed
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading
                .padding(.horizontal, Theme.fieldInset)
                .accessibilityHidden(true)
            preview
                .padding(.horizontal, Theme.fieldInset)
                .padding(.top, 6)
            actionRow
                .padding(.trailing, Theme.fieldInset)
                .padding(.top, 8)
        }
        .padding(.vertical, 12)
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

    // MARK: - heading: marker + word, source, badge, counts

    /// three complete candidates, chosen by what actually fits: one row;
    /// identity / source / badge with the counts beneath; everything stacked.
    /// accessibility sizes go straight to the stacked layout
    @ViewBuilder
    private var heading: some View {
        if dynamicTypeSize.isAccessibilitySize {
            headingStacked
        } else {
            ViewThatFits(in: .horizontal) {
                headingOneRow
                headingTwoRows
                headingStacked
            }
        }
    }

    private var headingOneRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            identity
            sourceText(separated: true)
            decodedBadge
            Spacer(minLength: 12)
            countsText
        }
    }

    private var headingTwoRows: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                identity
                sourceText(separated: true)
                decodedBadge
            }
            countsText
        }
    }

    private var headingStacked: some View {
        VStack(alignment: .leading, spacing: 4) {
            identity
            sourceText(separated: false)
            decodedBadge
            countsText
        }
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

    /// filename or source hint; yields first when the row is tight
    @ViewBuilder
    private func sourceText(separated: Bool) -> some View {
        if let source = meta.sourceLabel {
            Text(separated ? "· \(source)" : source)
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
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
                .foregroundStyle(Theme.inkSecondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 0.5)
                )
                .fixedSize()
        }
    }

    /// counts are measurements, so they keep the mono uppercase register
    @ViewBuilder
    private var countsText: some View {
        if let counts = session.counts(for: pane) {
            Text("\(counts.characters.formatted()) CHAR · \(counts.words.formatted()) WORD · \(counts.lines.formatted()) LINE")
                .font(Theme.dataSmall)
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(2)
        }
    }

    // MARK: - preview: pane-specific placeholder, or the first lines

    @ViewBuilder
    private var preview: some View {
        if text.isEmpty {
            Text(pane == .a ? "Tap to add original." : "Tap to add revision.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
        } else {
            Text(String(text.prefix(160)))
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
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

    private var actionsOneRow: some View {
        HStack(alignment: .center, spacing: 0) {
            pasteControl
            RowDivider()
            openFileAction
                .padding(.leading, 12)
            Spacer(minLength: 12)
            trailingAction(alignment: .trailing)
        }
        .frame(minHeight: 44)
    }

    private var actionsStacked: some View {
        VStack(alignment: .leading, spacing: 0) {
            pasteControl
            openFileAction
                .padding(.leading, Theme.fieldInset)
            trailingAction(alignment: .leading)
                .padding(.leading, Theme.fieldInset)
        }
    }

    /// the native paste control (fr-1), tinted to the field so only its label
    /// shows, laid out in a 44-point frame with a rectangular content shape.
    /// its label color on this fill and its interactive frame are verified on
    /// device (m3.1 acceptance); pasteboard access stays the system's
    private var pasteControl: some View {
        PasteButton(payloadType: String.self) { strings in
            Task { @MainActor in
                session.pasted(strings, into: pane)
            }
        }
        .labelStyle(.titleOnly)
        .controlSize(.small)
        .buttonBorderShape(.roundedRectangle(radius: Theme.fieldRadius))
        .tint(Theme.field)
        .foregroundStyle(Theme.ink)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var openFileAction: some View {
        TextAction(title: "Open File…", font: .subheadline, color: Theme.ink,
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
                TextAction(title: "Undo", font: .subheadline, color: Theme.ink,
                           horizontalPadding: 0, alignment: alignment) {
                    session.undoClear()
                }
                .accessibilityLabel("Undo clear of pane \(pane.rawValue)")
            }
        } else {
            TextAction(title: "Clear", font: .subheadline, color: Theme.inkSecondary,
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
