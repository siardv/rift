import SwiftUI

/// light/dark/system choice (fr-14)
enum AppearanceChoice: String, CaseIterable, Hashable {
    case system
    case light
    case dark

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// @AppStorage-backed viewer settings (sdd §5.1, §8, fr-14). a DynamicProperty
/// struct so any view holding one re-renders when a default changes; state
/// beyond viewer settings is deliberately not persisted in v1.0 (fr-15 later)
struct ViewerSettings: DynamicProperty {
    @AppStorage("viewer.fontScale") var fontScale: Double = 1.0
    @AppStorage("viewer.codeMonospaced") var codeMonospaced: Bool = true
    @AppStorage("viewer.appearance") var appearance: AppearanceChoice = .system
    @AppStorage("viewer.accessiblePalette") var accessiblePalette: Bool = false

    static let fontScaleRange: ClosedRange<Double> = 0.8...1.4
}
