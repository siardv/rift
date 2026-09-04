import SwiftUI

/// license, source link, privacy statement (sdd §5.1, §8)
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
                VStack(spacing: 10) {
                    Text("Rift")
                        .font(.system(size: 52, weight: .semibold))
                        .fontDesign(.serif)
                        .padding(.top, 28)
                    Text("See what actually changed.")
                        .font(.title3)
                        .fontDesign(.serif)
                        .foregroundStyle(.secondary)
                    Text("Version \(version)")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)

                    Divider()
                        .overlay(Theme.hairline)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 48)

                    VStack(spacing: 14) {
                        Text("Rift compares two texts at four strictness levels, reports where they converge, and keeps content changes separate from formatting noise. Everything it sets aside is counted, listed, and one tap away.")
                        Text("Fully offline. No accounts, no analytics, no network access at all.")
                    }
                    .font(.subheadline)
                    .fontDesign(.serif)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 28)

                    VStack(spacing: 8) {
                        Link("Source on GitHub", destination: URL(string: "https://github.com/siardv/rift")!)
                            .font(.subheadline)
                        Text("MIT license · © 2026 Siard van den Bosch")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                }
                .frame(maxWidth: .infinity)
            }
            .background(Theme.paper)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    AboutScreen()
}
