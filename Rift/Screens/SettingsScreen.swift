import SwiftUI

/// viewer settings (fr-14): font size, monospaced toggle for the code view,
/// light/dark/system, and the blue/orange accessible palette (nfr-5)
struct SettingsScreen: View {
    private var settings = ViewerSettings()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Text("A")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Slider(value: settings.$fontScale,
                               in: ViewerSettings.fontScaleRange,
                               step: 0.05)
                            .accessibilityLabel("Text size")
                            .accessibilityValue("\(Int((settings.fontScale * 100).rounded())) percent")
                        Text("A")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    Text("The quick brown fox jumps over the lazy dog.")
                        .font(.system(size: 17 * settings.fontScale, design: .serif))
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Text size")
                } footer: {
                    Text("Applies to the result views, on top of Dynamic Type.")
                }
                Section("Code view") {
                    Toggle("Monospaced (SF Mono)", isOn: settings.$codeMonospaced)
                }
                Section {
                    Picker("Appearance", selection: settings.$appearance) {
                        ForEach(AppearanceChoice.allCases, id: \.self) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Blue / orange palette", isOn: settings.$accessiblePalette)
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("The blue / orange palette replaces green and red for red–green color-vision deficiency. Glyphs, underline, and strikethrough always accompany color.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .navigationTitle("Viewing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SettingsScreen()
}
