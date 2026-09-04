import Foundation
import Observation
import RiftEngine
import UIKit
import os

/// which input pane (sdd §7.2)
enum PaneID: String, Sendable, Hashable {
    case a = "A"
    case b = "B"
}

/// per-pane provenance shown on the card (sdd §6.1, §9)
struct PaneMeta: Sendable, Equatable {
    /// filename or source hint; nil for typed/pasted text
    var sourceLabel: String?
    /// non-nil when a decoding fallback was used ("UTF-16", "Latin-1")
    var decodedAs: String?
}

/// per-side character/line/word counts (fr-11); computed off the main actor
struct TextCounts: Sendable, Equatable {
    var characters = 0
    var words = 0
    var lines = 0

    static func measure(_ text: String) -> TextCounts {
        guard !text.isEmpty else { return TextCounts() }
        var lines = 1
        var words = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            if scalar == "\n" {
                lines += 1
            }
            if scalar.properties.isWhitespace {
                inWord = false
            } else if !inWord {
                inWord = true
                words += 1
            }
        }
        if text.hasSuffix("\n") {
            lines -= 1
        }
        return TextCounts(characters: text.count, words: words, lines: lines)
    }
}

/// app-side ingestion (sdd §6.1): binary sniff, then utf-8 → utf-16 (bom) →
/// latin-1 lossy, with a visible "decoded as" badge for the fallbacks
enum Ingestion {
    enum DecodeResult: Sendable {
        case binary
        case text(String, decodedAs: String?)
    }

    static func decode(data: Data) -> DecodeResult {
        if sniffsBinary(data) {
            return .binary
        }
        var bytes = data
        // utf-8 bom: strip the marker bytes, still plain utf-8 (no badge)
        if bytes.count >= 3, bytes[bytes.startIndex] == 0xEF,
           bytes[bytes.index(bytes.startIndex, offsetBy: 1)] == 0xBB,
           bytes[bytes.index(bytes.startIndex, offsetBy: 2)] == 0xBF {
            bytes = bytes.dropFirst(3)
        }
        if let text = String(data: bytes, encoding: .utf8) {
            return .text(text, decodedAs: nil)
        }
        // utf-16 only when a bom says so (sdd §6.1)
        if data.count >= 2 {
            let b0 = data[data.startIndex]
            let b1 = data[data.index(data.startIndex, offsetBy: 1)]
            if (b0 == 0xFF && b1 == 0xFE) || (b0 == 0xFE && b1 == 0xFF),
               let text = String(data: data, encoding: .utf16) {
                return .text(text, decodedAs: "UTF-16")
            }
        }
        // latin-1 maps every byte, so this cannot fail; fallback kept for totality
        let text = String(data: data, encoding: .isoLatin1) ?? String(decoding: data, as: UTF8.self)
        return .text(text, decodedAs: "Latin-1")
    }

    /// nul byte or >10 % c0 controls (tab/lf/cr excluded) in the first 8 kb
    static func sniffsBinary(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        let sample = data.prefix(8192)
        var controls = 0
        for byte in sample {
            if byte == 0 { return true }
            if byte < 0x20 && byte != 0x09 && byte != 0x0A && byte != 0x0D {
                controls += 1
            }
        }
        return Double(controls) / Double(sample.count) > 0.10
    }
}

/// alert payload for refused input (sdd §9)
struct IngestionNotice: Identifiable, Sendable {
    let id = UUID()
    let message: String
}

/// snapshot for undoable clear (sdd §7.5: no confirmation dialogs)
struct ClearBackup: Sendable {
    let textA: String
    let textB: String
    let metaA: PaneMeta
    let metaB: PaneMeta
}

/// mode selection for the inspector's segmented control (fr-5)
enum ModeChoice: String, CaseIterable, Sendable, Hashable {
    case smart
    case strict
    case custom

    var label: String {
        switch self {
        case .smart: return "Smart"
        case .strict: return "Strict"
        case .custom: return "Custom"
        }
    }
}

/// thread-safe cancellation flag handed to the engine's isCancelled closure
/// (sdd §5.4); os lock instead of an actor so the check stays synchronous
final class CancelFlag: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)

    func cancel() {
        state.withLock { $0 = true }
    }

    var isCancelled: Bool {
        state.withLock { $0 }
    }
}

/// everything one debounced comparison produced, published atomically
private struct CompareOutcome: Sendable {
    let report: DiffReport?
    let viewModel: DiffViewModel?
    let countsA: TextCounts
    let countsB: TextCounts
    let wasCancelled: Bool
}

/// runs detection + ladder + diff off the main actor (sdd §5.4, nfr-1) and
/// prepares the render model in the same hop; never returns partial results
private func computeOutcome(a: String, b: String, options: CompareOptions,
                            flag: CancelFlag) async -> CompareOutcome {
    await Task.detached(priority: .userInitiated) { () -> CompareOutcome in
        let countsA = TextCounts.measure(a)
        let countsB = TextCounts.measure(b)
        // fr-2: compare only when both sides are non-empty (sdd §9)
        guard !a.isEmpty, !b.isEmpty else {
            return CompareOutcome(report: nil, viewModel: nil,
                                  countsA: countsA, countsB: countsB, wasCancelled: false)
        }
        guard let report = RiftEngine.compare(a, b, options: options,
                                              isCancelled: { flag.isCancelled }) else {
            return CompareOutcome(report: nil, viewModel: nil,
                                  countsA: countsA, countsB: countsB, wasCancelled: true)
        }
        let viewModel = DiffViewModel.build(report: report, a: a, b: b)
        return CompareOutcome(report: report, viewModel: viewModel,
                              countsA: countsA, countsB: countsB, wasCancelled: false)
    }.value
}

/// single source of truth for the compare screen (sdd §5.3): inputs, options,
/// the latest completed report, and the in-flight task. views render; this
/// schedules. no partial report is ever published (sdd §9)
@MainActor
@Observable
final class CompareSession {
    // MARK: - inputs

    var textA = "" { didSet { inputsChanged() } }
    var textB = "" { didSet { inputsChanged() } }
    var metaA = PaneMeta()
    var metaB = PaneMeta()
    private(set) var countsA: TextCounts?
    private(set) var countsB: TextCounts?

    // MARK: - options (fr-4, fr-5)

    var modeChoice: ModeChoice = .smart { didSet { if modeChoice != oldValue { inputsChanged() } } }
    var customRules = RuleSet() { didSet { if modeChoice == .custom, customRules != oldValue { inputsChanged() } } }
    var profileOverride: Profile? { didSet { if profileOverride != oldValue { inputsChanged() } } }

    // MARK: - output

    private(set) var report: DiffReport?
    private(set) var viewModel: DiffViewModel?
    private(set) var isComparing = false
    /// true once a run exceeds the 150 ms progress threshold (sdd §7.3)
    private(set) var showsProgress = false
    /// bumps on every published outcome; cheap onChange hook for views
    private(set) var publishCount = 0

    // MARK: - ui state

    /// fr-10: when true, formatting-only sites render dimmed in place
    var revealFormatting = false
    var ingestionNotice: IngestionNotice?
    private(set) var clearBackup: ClearBackup?

    // MARK: - scheduling

    private var generation = 0
    private var compareTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?
    private var flag: CancelFlag?

    nonisolated init() {}

    var currentOptions: CompareOptions {
        let mode: CompareOptions.Mode
        switch modeChoice {
        case .smart: mode = .smart
        case .strict: mode = .strict
        case .custom: mode = .custom(customRules)
        }
        return CompareOptions(mode: mode, profileOverride: profileOverride)
    }

    var hasAnyInput: Bool {
        !textA.isEmpty || !textB.isEmpty
    }

    func counts(for pane: PaneID) -> TextCounts? {
        pane == .a ? countsA : countsB
    }

    func meta(for pane: PaneID) -> PaneMeta {
        pane == .a ? metaA : metaB
    }

    func text(for pane: PaneID) -> String {
        pane == .a ? textA : textB
    }

    // MARK: - debounced auto-compare (fr-2, sdd §5.4)

    private func inputsChanged() {
        generation &+= 1
        let gen = generation
        flag?.cancel()
        compareTask?.cancel()
        progressTask?.cancel()
        if textA.isEmpty || textB.isEmpty {
            // sdd §9: one side empty produces no verdict; drop to the hint state
            report = nil
            viewModel = nil
            isComparing = false
            showsProgress = false
            if textA.isEmpty { countsA = nil }
            if textB.isEmpty { countsB = nil }
            if !hasAnyInput {
                return
            }
        }
        let a = textA
        let b = textB
        let options = currentOptions
        let newFlag = CancelFlag()
        flag = newFlag
        compareTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self, self.generation == gen else { return }
            self.isComparing = true
            self.beginProgressWindow(generation: gen)
            let outcome = await computeOutcome(a: a, b: b, options: options, flag: newFlag)
            guard self.generation == gen, !newFlag.isCancelled, !outcome.wasCancelled else {
                // cancelled: the latest completed report stays on screen (sdd §9)
                return
            }
            self.publish(outcome)
        }
    }

    private func beginProgressWindow(generation gen: Int) {
        progressTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self, self.generation == gen, self.isComparing else { return }
            self.showsProgress = true
        }
    }

    private func publish(_ outcome: CompareOutcome) {
        countsA = textA.isEmpty ? nil : outcome.countsA
        countsB = textB.isEmpty ? nil : outcome.countsB
        let hadContentChanges = (report?.verdict).map(Self.contentChangeCount).map { $0 > 0 } ?? false
        report = outcome.report
        viewModel = outcome.viewModel
        isComparing = false
        showsProgress = false
        publishCount &+= 1
        progressTask?.cancel()
        if let verdict = outcome.report?.verdict,
           Self.contentChangeCount(verdict) > 0, !hadContentChanges {
            // sdd §7.1: a single subtle haptic when a comparison completes with
            // content changes (fired on entering that state, not on every keystroke)
            Haptics.comparisonFoundContentChanges()
        }
    }

    private static func contentChangeCount(_ verdict: Verdict) -> Int {
        if case .changed(let contentChanges, _) = verdict {
            return contentChanges
        }
        return 0
    }

    // MARK: - mutations (fr-1, fr-11)

    func setText(_ text: String, for pane: PaneID, sourceLabel: String?, decodedAs: String?) {
        switch pane {
        case .a:
            metaA = PaneMeta(sourceLabel: sourceLabel, decodedAs: decodedAs)
            textA = text
        case .b:
            metaB = PaneMeta(sourceLabel: sourceLabel, decodedAs: decodedAs)
            textB = text
        }
    }

    func pasted(_ strings: [String], into pane: PaneID) {
        guard let text = strings.first else { return }
        setText(text, for: pane, sourceLabel: nil, decodedAs: nil)
    }

    func ingest(data: Data, filename: String?, into pane: PaneID) {
        Task { [weak self] in
            let result = await Task.detached { Ingestion.decode(data: data) }.value
            guard let self else { return }
            switch result {
            case .binary:
                let name = filename.map { " (\($0))" } ?? ""
                self.ingestionNotice = IngestionNotice(
                    message: "This looks like a binary file\(name). Rift compares plain text.")
            case .text(let text, let decodedAs):
                self.setText(text, for: pane, sourceLabel: filename, decodedAs: decodedAs)
            }
        }
    }

    func importFile(at url: URL, into pane: PaneID) {
        Task { [weak self] in
            let payload: (data: Data?, name: String) = await Task.detached {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                return ((try? Data(contentsOf: url)), url.lastPathComponent)
            }.value
            guard let self else { return }
            guard let data = payload.data else {
                self.ingestionNotice = IngestionNotice(
                    message: "Couldn't read \(payload.name).")
                return
            }
            self.ingest(data: data, filename: payload.name, into: pane)
        }
    }

    func clear(_ pane: PaneID, undoManager: UndoManager?) {
        snapshotForUndo(undoManager)
        setText("", for: pane, sourceLabel: nil, decodedAs: nil)
    }

    func clearAll(undoManager: UndoManager?) {
        snapshotForUndo(undoManager)
        metaA = PaneMeta()
        metaB = PaneMeta()
        textA = ""
        textB = ""
    }

    private func snapshotForUndo(_ undoManager: UndoManager?) {
        clearBackup = ClearBackup(textA: textA, textB: textB, metaA: metaA, metaB: metaB)
        undoManager?.registerUndo(withTarget: self) { target in
            Task { @MainActor in target.undoClear() }
        }
        undoManager?.setActionName("Clear")
    }

    func undoClear() {
        guard let backup = clearBackup else { return }
        clearBackup = nil
        metaA = backup.metaA
        metaB = backup.metaB
        textA = backup.textA
        textB = backup.textB
    }

    func swapSides() {
        let (a, b) = (textA, textB)
        let (ma, mb) = (metaA, metaB)
        let (ca, cb) = (countsA, countsB)
        metaA = mb
        metaB = ma
        countsA = cb
        countsB = ca
        textA = b
        textB = a
    }

    func loadSample() {
        metaA = PaneMeta(sourceLabel: "Example", decodedAs: nil)
        metaB = PaneMeta(sourceLabel: "Example", decodedAs: nil)
        textA = SampleContent.left
        textB = SampleContent.right
    }
}
