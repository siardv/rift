import RiftEngine
import SwiftUI

/// the progressive-disclosure home (sdd §7.2): mode control, profile
/// explanation, the ladder table, the formatting-site list (fr-10), and — in
/// custom mode only — the individual rule toggles (fr-5). a native grouped
/// list; only the type roles and the ladder grammar are rift's
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
                    ladderSection(report)
                    sitesSection
                }
            }
            .navigationTitle("Inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Theme.accent)
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
            return "Evaluates L0–L3; excluded differences remain inspectable."
        case .strict:
            return "Exact comparison; every difference is shown."
        case .custom:
            return "Uses the rules selected below."
        }
    }

    // MARK: - profile (fr-4)

    private func profileSection(_ report: DiffReport) -> some View {
        Section("Profile") {
            HStack {
                Text("\(report.profile.profile.rawValue.uppercased()) / \(report.profile.isAutomatic ? "AUTO" : "MANUAL")")
                    .font(Theme.label)
                    .accessibilityLabel("Content profile: \(report.profile.profile.rawValue), \(report.profile.isAutomatic ? "detected automatically" : "manual override")")
                Spacer()
                Picker("Override", selection: $session.profileOverride) {
                    Text("Automatic").tag(Profile?.none)
                    ForEach(Profile.allCases, id: \.self) { profile in
                        Text(profile.rawValue.capitalized).tag(Profile?.some(profile))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityLabel("Profile override")
            }
            Text(report.profile.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
            if report.profile.isAutomatic {
                Text("CONFIDENCE \(Int((report.profile.confidence * 100).rounded())) %")
                    .font(Theme.data)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Confidence \(Int((report.profile.confidence * 100).rounded())) percent")
            }
            if report.profile.isIndentationSensitive {
                Label("Indentation looks meaning-bearing; layout rules keep it significant.",
                      systemImage: "increase.indent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - ladder (sdd §3.2, §7.2)

    private func ladderSection(_ report: DiffReport) -> some View {
        Section {
            LadderView(ladder: report.ladder)
        } header: {
            Text("Strictness ladder")
        } footer: {
            Text("= equal at that level, ≠ still different; the last column counts formatting-only sites resolved exactly there. L1 line endings, NFC, invisibles, trailing space · L2 space runs, blank lines, NBSP, typography · L3 wrapping (prose) / indentation (code).")
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
                Text("Raw bytes on both sides, in document order: · space, ¶ newline, ⇥ tab, ⍽ NBSP, ␍ CR, ◦ invisible. The result's notation line reveals sites in place.")
            }
        }
    }

    private func siteRow(_ site: SiteDisplay) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(site.level.label)
                .font(Theme.data.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 24, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(site.excerptA)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                    Text("→")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(site.excerptB)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                }
                Text(site.level.displayName.lowercased())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
            ruleToggle("Unicode normalization (NFC)", isOn: $session.customRules.unicodeNFC)
            ruleToggle("Ignore invisible characters", isOn: $session.customRules.stripInvisibles)
            ruleToggle("Ignore trailing whitespace", isOn: $session.customRules.stripTrailingWhitespace)
        }
        Section("L2 · Spacing rules") {
            ruleToggle("Collapse space runs", isOn: $session.customRules.collapseSpaceRuns)
            ruleToggle("Collapse blank-line runs", isOn: $session.customRules.collapseBlankLines)
            ruleToggle("Trim outer blank lines", isOn: $session.customRules.trimOuterBlankLines)
            ruleToggle("Treat NBSP as space", isOn: $session.customRules.nbspToSpace)
            ruleToggle("Typographic equivalence (prose)", isOn: $session.customRules.typographicEquivalence)
        }
        Section("L3 · Layout rules") {
            ruleToggle("Reflow prose paragraphs", isOn: $session.customRules.reflowProse)
            ruleToggle("Ignore indentation (code)", isOn: $session.customRules.ignoreIndentation)
            ruleToggle("Ignore blank lines entirely (code)", isOn: $session.customRules.ignoreBlankLinesEntirely)
        }
        Section {
            ruleToggle("Ignore case", isOn: $session.customRules.ignoreCase)
            ruleToggle("Ignore punctuation", isOn: $session.customRules.ignorePunctuation)
        } header: {
            Text("Meaning-changing")
        } footer: {
            Text("These change meaning rather than layout, so they never join the automatic ladder. Off by default.")
        }
    }

    /// switches take the charcoal-led tint whose dark variant keeps the knob
    /// legible (sdd §7.1)
    private func ruleToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .tint(Theme.switchTint)
    }
}
