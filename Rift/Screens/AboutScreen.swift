import SwiftUI
import UIKit

/// about (sdd §5.1, §8): the supplied icon and a left-aligned factual
/// hierarchy — name, version, local-only processing, source, license. sans
/// throughout; no essay
struct AboutScreen: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return "\(short ?? "0.1.0") (\(build ?? "1"))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 16) {
                        AppIconView(side: 64)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Rift")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            Text("VERSION \(version)")
                                .font(Theme.data)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Version \(version)")
                        }
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 20)

                    RuleLine(weight: .rule)

                    Text("Local-only text comparison. No accounts, analytics, or network access.")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 16)

                    RuleLine()

                    factRow("SOURCE") {
                        Link("github.com/siardv/rift",
                             destination: URL(string: "https://github.com/siardv/rift")!)
                            .font(.subheadline)
                    }
                    RuleLine()
                    factRow("LICENSE") {
                        Text("MIT · © 2026 Siard van den Bosch")
                            .font(.subheadline)
                    }
                    RuleLine()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.paper)
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Theme.accent)
    }

    /// mono label column, sans value
    private func factRow<Content: View>(_ label: String, @ViewBuilder value: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(Theme.label)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            value()
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }
}

/// the app's own icon, read from the compiled bundle so the artwork exists
/// exactly once (the asset catalog's universal 1024 source); clipped to the
/// same continuous corner the home screen applies, so it looks like the icon
/// and not like an unmasked square
struct AppIconView: View {
    let side: CGFloat

    var body: some View {
        if let image = Self.bundledIcon() {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous))
                .accessibilityLabel("Rift app icon")
        } else {
            RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 0.5)
                .frame(width: side, height: side)
                .accessibilityHidden(true)
        }
    }

    /// CFBundleIcons → CFBundlePrimaryIcon → last (largest) CFBundleIconFiles
    /// entry, the names the asset compiler writes into the generated info.plist.
    /// nil in previews and unit tests, which have no compiled icon
    private static func bundledIcon() -> UIImage? {
        let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        let files = primary?["CFBundleIconFiles"] as? [String]
        guard let name = files?.last else { return nil }
        return UIImage(named: name)
    }
}

#Preview {
    AboutScreen()
}
