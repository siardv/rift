import RiftEngine
import SwiftUI
import UIKit

/// canonical verdict copy (sdd §3.4) — shared by voiceover, the copy action,
/// and the exported summary so the app never says two different things.
/// `compact(_:)` is a separate, display-only rendering for the result header
/// (m3); it never replaces the canonical sentences anywhere they are spoken,
/// copied, or exported
enum VerdictText {
    static func primary(_ verdict: Verdict) -> String {
        switch verdict {
        case .identical:
            return "Identical."
        case .formattingOnly:
            return "Same content."
        case .changed(let contentChanges, _):
            return contentChanges == 1 ? "1 content change." : "\(contentChanges) content changes."
        }
    }

    static func secondary(_ verdict: Verdict) -> String? {
        switch verdict {
        case .identical:
            return "byte-for-byte"
        case .formattingOnly(let level, let count):
            let places = count == 1 ? "1 place" : "\(count) places"
            switch level {
            case .exact:
                return "byte-for-byte"
            case .encoding:
                return "differ only in line endings / trailing space — \(places)"
            case .spacing:
                return "differ only in spacing / blank lines — \(places)"
            case .layout:
                return "differ only in layout (wrapping / indentation) — \(places)"
            }
        case .changed(_, let formattingOnly):
            guard formattingOnly > 0 else { return nil }
            return formattingOnly == 1
                ? "plus 1 formatting-only difference"
                : "plus \(formattingOnly) formatting-only differences"
        }
    }

    /// compact analytical notation for the visual secondary line (sdd §7.1):
    /// `L0 · exact`, `L2 · spacing only · 3 sites`, `5 formatting sites`.
    /// nil exactly when `secondary(_:)` is nil, so the reveal control appears
    /// in the same states as before
    static func compact(_ verdict: Verdict) -> String? {
        switch verdict {
        case .identical:
            return "L0 · exact"
        case .formattingOnly(let level, let count):
            let sites = count == 1 ? "1 site" : "\(count) sites"
            switch level {
            case .exact:
                return "L0 · exact"
            case .encoding:
                return "L1 · encoding only · \(sites)"
            case .spacing:
                return "L2 · spacing only · \(sites)"
            case .layout:
                return "L3 · layout only · \(sites)"
            }
        case .changed(_, let formattingOnly):
            guard formattingOnly > 0 else { return nil }
            return formattingOnly == 1 ? "1 formatting site" : "\(formattingOnly) formatting sites"
        }
    }

    static func contentChangeCount(_ verdict: Verdict) -> Int {
        if case .changed(let contentChanges, _) = verdict {
            return contentChanges
        }
        return 0
    }

    static func formattingCount(_ verdict: Verdict) -> Int {
        switch verdict {
        case .identical:
            return 0
        case .formattingOnly(_, let count):
            return count
        case .changed(_, let formattingOnly):
            return formattingOnly
        }
    }
}

/// a modest system-font verdict with visible Show / Hide formatting control.
/// canonical spoken, copied and exported wording remains unchanged
struct VerdictBanner: View {
    let verdict: Verdict
    let revealActive: Bool
    let onJumpToFirstChange: () -> Void
    let onToggleReveal: () -> Void

    @State private var showsCopied = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var verdictSize: CGFloat = 26

    private var canJump: Bool {
        VerdictText.contentChangeCount(verdict) > 0
    }

    private var canReveal: Bool {
        VerdictText.formattingCount(verdict) > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(VerdictText.primary(verdict))
                    .font(Theme.verdict(verdictSize))
                    .foregroundStyle(Theme.ink)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if canJump { onJumpToFirstChange() }
                    }
                    .onLongPressGesture {
                        copyVerdict()
                    }
                if showsCopied {
                    Text("COPIED")
                        .font(Theme.data)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if let compact = VerdictText.compact(verdict) {
                // the notation retains its wording; Show / Hide labels the
                // existing reveal action with a genuine 44-point target
                if canReveal {
                    Button(action: onToggleReveal) {
                        secondLine(compact)
                    }
                    .buttonStyle(.plain)
                } else {
                    secondLine(compact)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(canJump ? .isButton : [])
        .accessibilityAction(named: "Copy verdict") { copyVerdict() }
        .accessibilityAction(named: revealActive
                             ? "Hide formatting differences" : "Reveal formatting differences") {
            if canReveal { onToggleReveal() }
        }
        .accessibilityAction(named: "Jump to first change") {
            if canJump { onJumpToFirstChange() }
        }
    }

    /// notation and reveal label stack at accessibility text sizes
    private func secondLine(_ compact: String) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
        return layout {
            Text(compact)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
            if canReveal {
                Text(revealActive ? "Hide" : "Show")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
            }
        }
        .frame(minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// canonical primary + secondary sentences (sdd §3.4), never the compact form
    private var accessibilityText: String {
        var text = VerdictText.primary(verdict)
        if let secondary = VerdictText.secondary(verdict) {
            text += " " + secondary
        }
        return text
    }

    private func copyVerdict() {
        var sentence = VerdictText.primary(verdict)
        if let secondary = VerdictText.secondary(verdict) {
            sentence += " " + secondary.prefix(1).capitalized + secondary.dropFirst() + "."
        }
        UIPasteboard.general.string = sentence
        showsCopied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            showsCopied = false
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 24) {
        VerdictBanner(verdict: .identical, revealActive: false,
                      onJumpToFirstChange: {}, onToggleReveal: {})
        VerdictBanner(verdict: .formattingOnly(level: .layout, count: 3), revealActive: false,
                      onJumpToFirstChange: {}, onToggleReveal: {})
        VerdictBanner(verdict: .changed(contentChanges: 2, formattingOnly: 5), revealActive: true,
                      onJumpToFirstChange: {}, onToggleReveal: {})
    }
    .padding()
    .background(Theme.paper)
}
