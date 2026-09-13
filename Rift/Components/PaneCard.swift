import Foundation
import RiftEngine
import SwiftUI
import UniformTypeIdentifiers

/// one input pane as a document well (fr-1, sdd §7.2): a transparent field on
/// the workspace, defined by a firm top rule and a quieter bottom hairline —
/// first lines + counts, paste / file / clear, tap to edit, drag & drop target.
/// the type keeps its m2 name; only the presentation changed in m3
struct PaneCard: View {
    let pane: PaneID
    @Bindable var session: CompareSession
    /// true when this pane is empty while the other side already has text —
    /// the "waiting" state (sdd §7.3)
    let hintEmphasized: Bool
    let onRequestImport: (PaneID) -> Void

    @State private var isEditorPresented = false
    @State private var isDropTargeted = false
    @Environment(\.undoManager) private var undoManager

    private var text: String {
        session.text(for: pane)
    }

    private var meta: PaneMeta {
        session.meta(for: pane)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RuleLine(weight: .rule)
            VStack(alignment: .leading, spacing: 6) {
                header
                preview
                footer
            }
            .padding(.horizontal, 2)
            .padding(.top, 8)
            .padding(.bottom, 2)
            RuleLine()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            // drop feedback: a restrained low-radius outline, nothing filled
            RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                .stroke(Theme.ink, lineWidth: isDropTargeted ? 1 : 0)
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

    // MARK: - header: `A / ORIGINAL`, source, decoded-as badge

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(pane == .a ? "A / ORIGINAL" : "B / REVISION")
                .font(Theme.label)
                .foregroundStyle(Theme.ink)
            if let source = meta.sourceLabel {
                Text(source)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
            if let decoded = meta.decodedAs {
                Text("DECODED AS \(decoded.uppercased())")
                    .font(Theme.dataSmall)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                            .stroke(Theme.hairline, lineWidth: 0.5)
                    )
                    .accessibilityLabel("decoded as \(decoded)")
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - preview: first lines, or the literal state

    @ViewBuilder
    private var preview: some View {
        if text.isEmpty {
            Text(emptyStateText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 2)
        } else {
            Text(String(text.prefix(160)))
                .font(.footnote)
                .lineLimit(2)
                .foregroundStyle(.primary)
        }
    }

    /// literal states (sdd §7.3): what the pane holds, not what to do
    private var emptyStateText: String {
        guard hintEmphasized else { return "No text" }
        return pane == .a ? "Add original" : "Waiting for revision"
    }

    // MARK: - footer: textual actions + compact counts

    private var footer: some View {
        HStack(alignment: .center, spacing: 6) {
            PasteButton(payloadType: String.self) { strings in
                Task { @MainActor in
                    session.pasted(strings, into: pane)
                }
            }
            .labelStyle(.titleOnly)
            .buttonBorderShape(.roundedRectangle(radius: Theme.fieldRadius))
            .controlSize(.small)
            .tint(Theme.pasteTint)

            TextAction(title: "File") {
                onRequestImport(pane)
            }
            .accessibilityLabel("Import from Files")

            TextAction(title: "Clear") {
                session.clear(pane, undoManager: undoManager)
            }
            .disabled(text.isEmpty)
            .accessibilityLabel("Clear pane \(pane.rawValue)")

            Spacer(minLength: 0)

            if let counts = session.counts(for: pane) {
                Text("\(counts.characters.formatted()) CHAR · \(counts.words.formatted()) WORD · \(counts.lines.formatted()) LINE")
                    .font(Theme.dataSmall)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityLabel("\(counts.characters) characters, \(counts.words) words, \(counts.lines) lines")
            }
        }
    }

    private var accessibilitySummary: String {
        let role = pane == .a ? "original" : "revision"
        if text.isEmpty {
            return "Pane \(pane.rawValue), \(role), empty. Double-tap to type."
        }
        let counts = session.counts(for: pane)
        let detail = counts.map { "\($0.characters) characters, \($0.words) words, \($0.lines) lines" } ?? ""
        return "Pane \(pane.rawValue), \(role), \(detail). Double-tap to edit."
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
                .navigationTitle(pane == .a ? "A / Original" : "B / Revision")
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
