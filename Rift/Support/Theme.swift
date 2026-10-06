import SwiftUI
import UIKit

/// the approved neutral native workspace: white and gray surfaces, charcoal
/// actions, system interface typography and restrained analytical rules.
/// semantic change colors and their non-color markings remain unchanged
enum Theme {
    // MARK: - grounds and ink

    static let paper: Color = dynamic(
        light: UIColor(white: 245 / 255, alpha: 1),
        dark: UIColor(white: 24 / 255, alpha: 1))

    static let ink: Color = Color(uiColor: inkUIColor)

    static var inkUIColor: UIColor {
        UIColor { traits in
            UIColor(white: traits.userInterfaceStyle == .dark ? 245 / 255 : 32 / 255, alpha: 1)
        }
    }

    static let inkSecondary: Color = dynamic(
        light: UIColor(white: 102 / 255, alpha: 1),
        dark: UIColor(white: 184 / 255, alpha: 1))

    static let field: Color = Color(uiColor: fieldUIColor)

    static var fieldUIColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 37 / 255, alpha: 1)
                : .white
        }
    }

    static let fieldEdge: Color = dynamic(
        light: UIColor(white: 224 / 255, alpha: 1),
        dark: UIColor(white: 65 / 255, alpha: 1))

    static var actionUIColor: UIColor {
        UIColor { traits in
            UIColor(white: traits.userInterfaceStyle == .dark ? 245 / 255 : 37 / 255, alpha: 1)
        }
    }

    static var actionLabelUIColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(white: 32 / 255, alpha: 1) : .white
        }
    }

    /// one-point rule where regions genuinely differ (result / evidence
    /// boundary, ladder convergence, navigator edge); never on a field
    static let rule: Color = ink

    /// half-point hairline for secondary subdivisions in the result views (row
    /// separators, side-by-side gutters, the copy row); fields use `fieldEdge`
    static let hairline: Color = Color.primary.opacity(0.22)

    /// faint fill marking an absent line in a side-by-side pair; a placeholder,
    /// not a hierarchy device
    static let absentFill: Color = Color.primary.opacity(0.05)

    static let accent: Color = ink

    static let switchTint: Color = dynamic(
        light: UIColor(white: 37 / 255, alpha: 1),
        dark: UIColor(white: 138 / 255, alpha: 1))

    /// formatting-only ink: dimmed to ~40 % with a dotted underline (sdd §7.1)
    static let formattingOpacity: Double = 0.4

    // MARK: - shape and metrics

    static let fieldRadius: CGFloat = 8
    static let sourceGroupRadius: CGFloat = 16

    /// horizontal inset of field content (heading, meta line, excerpt)
    static let fieldInset: CGFloat = 13

    /// the paste control's own internal label padding (estimated from the
    /// device capture; adjust after measuring). the action row is inset by
    /// `fieldInset - pasteControlPadding`, never by a negative value, so the
    /// Paste label shares the content's left edge
    static let pasteControlPadding: CGFloat = 8

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

    static func verdict(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold)
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
