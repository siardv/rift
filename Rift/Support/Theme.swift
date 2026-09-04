import SwiftUI
import UIKit

/// design tokens for the "academic-clean" register (sdd §7.1): paper-toned
/// neutrals, serif display type, restrained accessible change colors, and the
/// optional blue/orange palette for red-green color vision deficiency (nfr-5)
enum Theme {
    // MARK: - grounds

    /// warm off-white light / near-black warm dark
    static let paper: Color = dynamic(
        light: UIColor(red: 0.980, green: 0.973, blue: 0.960, alpha: 1),
        dark: UIColor(red: 0.086, green: 0.084, blue: 0.078, alpha: 1))

    /// input cards and sheets sit barely off the paper
    static let card: Color = dynamic(
        light: UIColor(red: 0.955, green: 0.947, blue: 0.930, alpha: 1),
        dark: UIColor(red: 0.135, green: 0.132, blue: 0.124, alpha: 1))

    static let hairline: Color = Color.primary.opacity(0.14)

    /// formatting-only ink: dimmed to ~40 % with a dotted underline (sdd §7.1)
    static let formattingOpacity: Double = 0.4

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

    // MARK: - type

    /// base sizes; views scale these by dynamic type (@ScaledMetric) and the
    /// fr-14 font-size setting
    static let proseBaseSize: CGFloat = 17
    static let codeBaseSize: CGFloat = 13

    static func banner(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }

    // MARK: - helpers

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}
