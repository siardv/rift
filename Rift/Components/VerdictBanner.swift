import RiftEngine
import SwiftUI
import UIKit

/// canonical banner copy (sdd §3.4) — shared by the banner, voiceover, and the
/// exported summary so the app never says two different things
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

/// the identity moment of the app (sdd §7.1): one serif sentence set large,
/// with the quiet secondary line beneath. long-press copies the sentence, tap
/// jumps to the first content change, tapping the secondary line reveals the
/// formatting-only sites dimmed in place (sdd §3.4, fr-10)
struct VerdictBanner: View {
    let verdict: Verdict
    let revealActive: Bool
    let onJumpToFirstChange: () -> Void
    let onToggleReveal: () -> Void

    @State private var showsCopied = false
    @ScaledMetric(relativeTo: .largeTitle) private var bannerSize: CGFloat = 32

    private var canJump: Bool {
        VerdictText.contentChangeCount(verdict) > 0
    }

    private var canReveal: Bool {
        VerdictText.formattingCount(verdict) > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(VerdictText.primary(verdict))
                    .font(Theme.banner(bannerSize))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if canJump { onJumpToFirstChange() }
                    }
                    .onLongPressGesture {
                        copyVerdict()
                    }
                if showsCopied {
                    Label("Copied", systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
                Spacer(minLength: 0)
            }
            if let secondary = VerdictText.secondary(verdict) {
                Button {
                    if canReveal { onToggleReveal() }
                } label: {
                    HStack(spacing: 5) {
                        Text(secondary)
                            .font(.subheadline)
                            .fontDesign(.serif)
                        if canReveal {
                            Image(systemName: revealActive ? "eye.fill" : "eye")
                                .font(.caption2)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canReveal)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(canJump ? .isButton : [])
        .accessibilityAction(named: "Copy verdict") { copyVerdict() }
        .accessibilityAction(named: "Reveal formatting differences") {
            if canReveal { onToggleReveal() }
        }
        .accessibilityAction(named: "Jump to first change") {
            if canJump { onJumpToFirstChange() }
        }
    }

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
}
