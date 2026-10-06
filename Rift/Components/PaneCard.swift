import Foundation
import RiftEngine
import SwiftUI
import UniformTypeIdentifiers

/// one source row with a stable editor, expanded only by explicit selection
struct PaneCard: View {
    let pane: PaneID
    @Bindable var session: CompareSession
    let onRequestImport: (PaneID) -> Void
    let focus: FocusState<PaneID?>.Binding
    let isExpanded: Bool
    let editingViewportHeight: CGFloat
    let onSelect: () -> Void

    @State private var isDropTargeted = false
    @State private var showsDetails = false
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var editorHeight: CGFloat = 212

    private var text: String { session.text(for: pane) }
    private var meta: PaneMeta { session.meta(for: pane) }
    private var word: String { pane == .a ? "Original" : "Revision" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading
            // keep native editing and typing undo alive across collapse/reopen
            VStack(alignment: .leading, spacing: 8) {
                editor
                actionRow
            }
            .padding(.top, 8)
            .frame(height: isExpanded ? nil : 0)
            .clipped()
            .opacity(isExpanded ? 1 : 0)
            .allowsHitTesting(isExpanded)
            .accessibilityHidden(!isExpanded)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, isExpanded ? 16 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: Theme.fieldRadius)
                    .strokeBorder(Theme.ink, lineWidth: 1)
            }
        }
        .onDrop(of: [.fileURL, .plainText], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .accessibilityElement(children: .contain)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 4) {
                Button(action: onSelect) {
                    HStack(alignment: .center, spacing: 8) {
                        let layout = dynamicTypeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                            : AnyLayout(HStackLayout(spacing: 8))
                        layout {
                            Text(word)
                                .font(.body.weight(.medium))
                                .foregroundStyle(Theme.ink)
                            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                            Text(wordCount)
                                .font(.caption)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(word) source")
                .accessibilityValue(isExpanded ? "Expanded, \(wordCount)" : "Collapsed, \(wordCount)")
                .accessibilityHint(isExpanded ? "Closes this source editor" : "Opens this source editor")
                trailingAction
            }
            if let source = meta.sourceLabel {
                Text(source)
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let decoded = meta.decodedAs {
                Label("Decoded as \(decoded)", systemImage: "info.circle")
                    .font(.caption.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var wordCount: String {
        guard !text.isEmpty else { return "Empty" }
        guard let counts = session.counts(for: pane) else { return "Updating…" }
        return "\(counts.words.formatted()) \(counts.words == 1 ? "word" : "words")"
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: pane == .a ? $session.textA : $session.textB)
                .font(.body)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .scrollContentBackground(.hidden)
                .focused(focus, equals: pane)
                .accessibilityLabel("\(word) text")
                .accessibilityHint("Edit directly, or use Paste or Open File to replace this source")
            if text.isEmpty {
                Text(pane == .a ? "Paste or type original text" : "Paste or type revision text")
                    .font(.body)
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: activeEditorHeight)
        .id(pane)
    }

    private var activeEditorHeight: CGFloat {
        let preferredHeight = max(212, editorHeight)
        guard focus.wrappedValue == pane, editingViewportHeight > 0 else { return preferredHeight }
        return min(preferredHeight, editingViewportHeight)
    }

    @ViewBuilder
    private var actionRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            actionsStacked
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    pasteControl
                    openFileAction
                    Spacer(minLength: 0)
                    detailsAction
                }
                actionsStacked
            }
        }
    }

    private var actionsStacked: some View {
        VStack(alignment: .leading, spacing: 0) {
            pasteControl
            openFileAction
            detailsAction
        }
    }

    private var pasteControl: some View {
        PasteControl { strings in session.pasted(strings, into: pane) }
            .id(colorScheme)
            .fixedSize()
            .frame(minHeight: 44)
            .accessibilityLabel("Paste into \(word.lowercased())")
    }

    private var openFileAction: some View {
        Button {
            onRequestImport(pane)
        } label: {
            Label("Open File", systemImage: "folder")
                .font(.subheadline)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open a file for \(word.lowercased())")
    }

    private var detailsAction: some View {
        Button {
            focus.wrappedValue = nil
            showsDetails = true
        } label: {
            Image(systemName: "info.circle")
                .font(.subheadline)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.inkSecondary)
        .accessibilityLabel("Source details for \(word.lowercased())")
        .popover(isPresented: $showsDetails) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(word) source")
                    .font(.headline)
                if let source = meta.sourceLabel { Text(source) }
                if let decoded = meta.decodedAs { Text("Decoded as \(decoded)") }
                if let counts = session.counts(for: pane) {
                    Text(Self.countsPhrase(counts))
                } else {
                    Text(text.isEmpty ? "Empty" : "Updating counts…")
                }
            }
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .frame(idealWidth: 280)
            .presentationCompactAdaptation(.popover)
            .presentationBackground(Theme.paper)
        }
    }

    @ViewBuilder
    private var trailingAction: some View {
        if text.isEmpty {
            if session.undoablePane == pane {
                TextAction(title: "Undo", font: .subheadline, horizontalPadding: 0) {
                    session.undoClear()
                }
                .accessibilityLabel("Undo clear of \(word.lowercased())")
            }
        } else {
            Button {
                focus.wrappedValue = nil
                session.clear(pane, undoManager: undoManager)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.inkSecondary)
            .accessibilityLabel("Clear \(word.lowercased())")
        }
    }

    private static func countsPhrase(_ counts: TextCounts) -> String {
        func unit(_ value: Int, _ singular: String) -> String {
            "\(value.formatted()) \(singular)\(value == 1 ? "" : "s")"
        }
        return unit(counts.words, "word") + " · " + unit(counts.lines, "line")
            + " · " + unit(counts.characters, "character")
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
