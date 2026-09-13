import SwiftUI
import UIKit

/// design tokens for the "quiet editorial instrument" register (sdd §7.1, m3
/// refined by m3.1): the icon's ivory workspace and charcoal ink; input fields
/// as a faintly lifted paper surface with a crisp low-contrast edge; one-point
/// rules and half-point hairlines only where regions are genuinely analytical;
/// one low radius; no authored shadows; three strictly limited type roles
/// (serif, sans, mono). the accessible change colors and their non-color
/// markings are unchanged from m2 (nfr-5)
enum Theme {
    // MARK: - identity colors (match the supplied icon exactly)

    /// warm ivory #F5F1E7
    private static var ivory: UIColor { UIColor(red: 0.961, green: 0.945, blue: 0.906, alpha: 1) }
    /// deep charcoal #1F1E1C
    private static var charcoal: UIColor { UIColor(red: 0.122, green: 0.118, blue: 0.110, alpha: 1) }

    // MARK: - grounds and ink

    /// the workspace: ivory in light, charcoal in dark
    static let paper: Color = dynamic(light: ivory, dark: charcoal)

    /// primary ink and structural rules: charcoal on ivory, ivory on charcoal
    static let ink: Color = dynamic(light: charcoal, dark: ivory)

    /// explicit secondary ink for pane words, placeholders, sources, counts,
    /// the empty-result instruction and the subordinate Clear action: an opaque
    /// warm grey rather than an opacity of the ink, so hierarchy never rests on
    /// transparency and body-text contrast holds on both the canvas and the
    /// field (light 5.4:1 / 5.7:1, dark 7.5:1 / 6.8:1)
    static let inkSecondary: Color = dynamic(
        light: UIColor(red: 0.388, green: 0.384, blue: 0.365, alpha: 1), // #63625D
        dark: UIColor(red: 0.694, green: 0.678, blue: 0.651, alpha: 1)) // #B1ADA6

    /// the input field: paper lifted toward white in light (1.05:1 against the
    /// canvas), charcoal lifted toward ivory in dark (1.11:1). also the tint
    /// that lets the native PasteButton merge with the field it sits in
    static let field: Color = dynamic(
        light: UIColor(red: 0.976, green: 0.969, blue: 0.945, alpha: 1), // #F9F7F1
        dark: UIColor(red: 0.157, green: 0.149, blue: 0.141, alpha: 1)) // #282624

    /// the crisp one-point edge of a field, the action-row divider and the
    /// Load sample outline (1.50:1 against the canvas in light). if the
    /// boundary is not immediately perceptible on the device at ordinary and
    /// low brightness, this is the token to darken one step — never a shadow
    /// or a stronger fill
    static let fieldEdge: Color = dynamic(
        light: UIColor(red: 0.792, green: 0.780, blue: 0.745, alpha: 1), // #CAC7BE
        dark: UIColor(red: 0.290, green: 0.282, blue: 0.271, alpha: 1)) // #4A4845

    /// one-point rule where regions genuinely differ (result / evidence
    /// boundary, ladder convergence, navigator edge); never on a field
    static let rule: Color = ink

    /// half-point hairline for secondary subdivisions in the result views (row
    /// separators, side-by-side gutters, the copy row); fields use `fieldEdge`
    static let hairline: Color = Color.primary.opacity(0.22)

    /// faint fill marking an absent line in a side-by-side pair; a placeholder,
    /// not a hierarchy device
    static let absentFill: Color = Color.primary.opacity(0.05)

    /// neutral interaction tint: charcoal-led instead of system blue. dark mode
    /// inverts to ivory so buttons and links read as ink
    static let accent: Color = dynamic(light: charcoal, dark: ivory)

    /// switch tracks: charcoal in light; a mid warm grey in dark so the white
    /// knob stays legible against the track (an ivory track would swallow it)
    static let switchTint: Color = dynamic(
        light: charcoal,
        dark: UIColor(red: 0.561, green: 0.541, blue: 0.502, alpha: 1))

    /// formatting-only ink: dimmed to ~40 % with a dotted underline (sdd §7.1)
    static let formattingOpacity: Double = 0.4

    // MARK: - shape and metrics

    /// the only custom radius in the app: fields, the decoded-as badge, the
    /// PasteButton border and the Load sample outline; native controls
    /// otherwise keep system shapes
    static let fieldRadius: CGFloat = 4

    /// horizontal inset of field content: the native PasteButton's internal
    /// label padding at `.small` (13 pt measured on device), so the heading,
    /// the placeholder and the Paste label share one left edge without any
    /// negative padding
    static let fieldInset: CGFloat = 13

    // MARK: - change colors (nfr-5: aa contrast, color never the sole channel)

    static func insertInk(accessible: Bool) -> Color {
        accessible
            ? dynamic(light: UIColor(red: 0.05, green: 0.33, blue: 0.75, alpha: 1),
                      dark: UIColor(red: 0.52, green: 0.72, blue: 1.00, alpha: 1))
            : dynamic(light: UIColor(red: 0.09, green: 0.44, blue: 0.22, alpha: 1),
                      dark: UIColor(red: 0.45, green: 0.83, blue: 0.55, alpha: 1))
    }

    static func deleteInk(accessible: Bool) -> Color {
        accessible
            ? dynamic(light: UIColor(red: 0.64, green: 0.33, blue: 0.00, alpha: 1),
                      dark: UIColor(red: 1.00, green: 0.68, blue: 0.32, alpha: 1))
            : dynamic(light: UIColor(red: 0.66, green: 0.15, blue: 0.15, alpha: 1),
                      dark: UIColor(red: 0.94, green: 0.52, blue: 0.50, alpha: 1))
    }

    static func insertWash(accessible: Bool) -> Color {
        accessible
            ? dynamic(light: UIColor(red: 0.05, green: 0.33, blue: 0.75, alpha: 0.13),
                      dark: UIColor(red: 0.52, green: 0.72, blue: 1.00, alpha: 0.20))
            : dynamic(light: UIColor(red: 0.09, green: 0.50, blue: 0.24, alpha: 0.13),
                      dark: UIColor(red: 0.45, green: 0.83, blue: 0.55, alpha: 0.20))
    }

    static func deleteWash(accessible: Bool) -> Color {
        accessible
            ? dynamic(light: UIColor(red: 0.75, green: 0.38, blue: 0.00, alpha: 0.13),
                      dark: UIColor(red: 1.00, green: 0.68, blue: 0.32, alpha: 0.20))
            : dynamic(light: UIColor(red: 0.72, green: 0.16, blue: 0.16, alpha: 0.12),
                      dark: UIColor(red: 0.94, green: 0.52, blue: 0.50, alpha: 0.20))
    }

    // MARK: - type roles (sdd §7.1)

    /// base sizes; views scale these by dynamic type (@ScaledMetric) and the
    /// fr-14 font-size setting
    static let proseBaseSize: CGFloat = 17
    static let codeBaseSize: CGFloat = 13

    /// serif role 1 of 2: the principal verdict sentence (role 2 is flowing
    /// prose result text, set in ProseDiffView)
    static func verdict(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }

    /// mono eyebrow / structural label in the result header and sheets:
    /// `RESULT`, `PROSE / AUTO`, `UNIFIED`; never on the input fields
    static var label: Font { .caption.weight(.semibold).monospaced() }

    /// mono analytical metadata: counts, `L0–L3`, compact result notation
    static var data: Font { .caption.monospaced() }

    /// smaller mono metadata: pane counts, decoded-as badge
    static var dataSmall: Font { .caption2.monospaced() }

    // MARK: - helpers

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}
