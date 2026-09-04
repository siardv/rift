import RiftEngine
import SwiftUI

/// the progressive-disclosure home (sdd §7.2): mode control, profile
/// explanation, the ladder readout, the formatting-site list (fr-10), and —
/// in custom mode only — the individual rule toggles (fr-5)
struct InspectorSheet: View {
    @Bindable var session: CompareSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                modeSection
                if session.modeChoice == .custom {
                    ruleSections
                }
                if let report = session.report {
                    profileSection(report)
                    Section("Strictness ladder") {
                        LadderView(ladder: report.ladder)
                    }
                    sitesSection
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .navigationTitle("Inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - mode (fr-5)

    private var modeSection: some View {
        Section {
            Picker("Mode", selection: $session.modeChoice) {
                ForEach(ModeChoice.allCases, id: \.self) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            .pickerStyle(.segmented)
            Text(modeExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Mode")
        }
    }

    private var modeExplanation: String {
        switch session.modeChoice {
        case .smart:
            return "The full strictness ladder decides automatically. Everything set aside stays counted and revealable."
        case .strict:
            return "L0 only: every byte difference is shown, nothing is set aside."
        case .custom:
            return "The ladder runs with your rule choices below."
        }
    }

    // MARK: - profile (fr-4)

    private func profileSection(_ report: DiffReport) -> some View {
        Section("Profile") {
            HStack {
                Text("\(report.profile.profile.rawValue.capitalized) · \(report.profile.isAutomatic ? "auto" : "manual")")
                    .font(.subheadline)
                    .fontDesign(.serif)
                Spacer()
                Picker("Override", selection: $session.profileOverride) {
                    Text("Automatic").tag(Profile?.none)
                    ForEach(Profile.allCases, id: \.self) { profile in
                        Text(profile.rawValue.capitalized).tag(Profile?.some(profile))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            Text(report.profile.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
            if report.profile.isIndentationSensitive {
                Label("Indentation looks meaning-bearing; layout rules keep it significant.",
                      systemImage: "increase.indent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - formatting sites (fr-10)

    private var sitesSection: some View {
        let sites = session.viewModel?.sites ?? []
        return Section {
            if sites.isEmpty {
                Text("No formatting-only differences.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sites) { site in
                    siteRow(site)
                }
            }
        } header: {
            Text("Formatting-only sites (\(sites.count))")
        } footer: {
            if !sites.isEmpty {
                Text("Each site shows the raw bytes on both sides (· space, ¶ newline, ⇥ tab, ⍽ NBSP). Tapping the verdict's secondary line dims them in place.")
            }
        }
    }

    private func siteRow(_ site: SiteDisplay) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(site.level.label)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.hairline, lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(site.excerptA)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                    Text(site.excerptB)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                }
                Text(site.level.displayName.lowercased())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Formatting-only difference, level \(site.level.displayName): \(site.excerptA) became \(site.excerptB)")
    }

    // MARK: - custom rules (fr-5, appendix a)

    @ViewBuilder
    private var ruleSections: some View {
        Section("L1 · Encoding rules") {
            Toggle("Unicode normalization (NFC)", isOn: $session.customRules.unicodeNFC)
            Toggle("Ignore invisible characters", isOn: $session.customRules.stripInvisibles)
            Toggle("Ignore trailing whitespace", isOn: $session.customRules.stripTrailingWhitespace)
        }
        Section("L2 · Spacing rules") {
            Toggle("Collapse space runs", isOn: $session.customRules.collapseSpaceRuns)
            Toggle("Collapse blank-line runs", isOn: $session.customRules.collapseBlankLines)
            Toggle("Trim outer blank lines", isOn: $session.customRules.trimOuterBlankLines)
            Toggle("Treat NBSP as space", isOn: $session.customRules.nbspToSpace)
            Toggle("Typographic equivalence (prose)", isOn: $session.customRules.typographicEquivalence)
        }
        Section("L3 · Layout rules") {
            Toggle("Reflow prose paragraphs", isOn: $session.customRules.reflowProse)
            Toggle("Ignore indentation (code)", isOn: $session.customRules.ignoreIndentation)
            Toggle("Ignore blank lines entirely (code)", isOn: $session.customRules.ignoreBlankLinesEntirely)
        }
        Section {
            Toggle("Ignore case", isOn: $session.customRules.ignoreCase)
            Toggle("Ignore punctuation", isOn: $session.customRules.ignorePunctuation)
        } header: {
            Text("Meaning-changing")
        } footer: {
            Text("These change meaning rather than layout, so they never join the automatic ladder. Off by default.")
        }
    }
}
