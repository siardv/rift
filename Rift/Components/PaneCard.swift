import Foundation
import RiftEngine
import SwiftUI
import UniformTypeIdentifiers

/// one input pane as a collapsed card (fr-1, sdd §7.2): first lines + counts,
/// paste / files / clear, tap to edit, drag & drop target
struct PaneCard: View {
    let pane: PaneID
    @Bindable var session: CompareSession
    /// true when this pane is empty while the other side already has text —
    /// the "quiet hint on the other pane" state (sdd §7.3)
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
        VStack(alignment: .leading, spacing: 6) {
            header
            preview
            footer
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isDropTargeted ? Color.accentColor : Theme.hairline,
                                lineWidth: isDropTargeted ? 1.5 : 0.5)
                )
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

    private var header: some View {
        HStack(spacing: 6) {
            Text(pane.rawValue)
                .font(.subheadline.weight(.semibold))
                .fontDesign(.serif)
            Text(pane == .a ? "original" : "changed")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if let source = meta.sourceLabel {
                Text(source)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            if let decoded = meta.decodedAs {
                Text("decoded as \(decoded)")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if text.isEmpty {
            Text(hintEmphasized ? "Add the other side to compare." : "Paste, type, or drop text.")
                .font(.footnote)
                .fontDesign(.serif)
                .foregroundStyle(hintEmphasized ? Color.secondary : Color.secondary.opacity(0.7))
                .padding(.vertical, 2)
        } else {
            Text(String(text.prefix(160)))
                .font(.footnote)
                .lineLimit(2)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            PasteButton(payloadType: String.self) { strings in
                Task { @MainActor in
                    session.pasted(strings, into: pane)
                }
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.capsule)
            .controlSize(.small)

            Button {
                onRequestImport(pane)
            } label: {
                Label("Files", systemImage: "folder")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .accessibilityLabel("Import from Files")

            Button {
                session.clear(pane, undoManager: undoManager)
            } label: {
                Label("Clear", systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .disabled(text.isEmpty)
            .accessibilityLabel("Clear pane \(pane.rawValue)")

            Spacer(minLength: 0)

            if let counts = session.counts(for: pane) {
                Text("\(counts.characters.formatted()) ch · \(counts.words.formatted()) w · \(counts.lines.formatted()) ln")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .accessibilityLabel("\(counts.characters) characters, \(counts.words) words, \(counts.lines) lines")
            }
        }
    }

    private var accessibilitySummary: String {
        if text.isEmpty {
            return "Pane \(pane.rawValue), empty. Double-tap to type."
        }
        let counts = session.counts(for: pane)
        let detail = counts.map { "\($0.characters) characters, \($0.words) words, \($0.lines) lines" } ?? ""
        return "Pane \(pane.rawValue), \(detail). Double-tap to edit."
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

/// full-screen editor reached by tapping a pane card (fr-1: direct typing);
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
                .navigationTitle(pane == .a ? "A — original" : "B — changed")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .onAppear { isFocused = true }
    }
}
