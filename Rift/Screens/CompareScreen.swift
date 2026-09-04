import RiftEngine
import SwiftUI
import UniformTypeIdentifiers

/// the single main screen (sdd §7.2): input panes, verdict banner, result
/// view, floating change navigation; inspector and settings live in sheets.
/// the screen renders CompareSession state and never computes (sdd §1.5, §5.3)
struct CompareScreen: View {
    @State private var session = CompareSession()
    private var settings = ViewerSettings()

    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass

    @State private var isInspectorPresented = false
    @State private var isSettingsPresented = false
    @State private var isAboutPresented = false
    @State private var isProfilePresented = false
    @State private var isImporterPresented = false
    @State private var importTarget: PaneID?
    @State private var presentationOverride: DiffPresentation?
    @State private var currentChange = 0

    private static let importTypes: [UTType] = [
        .plainText, .text, .sourceCode, .json, .xml, .yaml, .commaSeparatedText, .log,
    ]

    // MARK: - layout defaults (sdd §7.2, fr-7)

    private var isWide: Bool {
        hSizeClass == .regular || vSizeClass == .compact
    }

    private var presentation: DiffPresentation {
        presentationOverride ?? (isWide ? .sideBySide : .unified)
    }

    private var changeAnchors: [ChangeAnchor] {
        session.viewModel?.changes ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    VStack(spacing: 0) {
                        header(proxy: proxy)
                        resultArea
                    }
                    if !changeAnchors.isEmpty, session.report != nil {
                        ChangeNavigator(
                            total: changeAnchors.count,
                            current: currentChange,
                            onPrevious: { navigate(by: -1, proxy: proxy) },
                            onNext: { navigate(by: 1, proxy: proxy) })
                    }
                }
                .background(Theme.paper.ignoresSafeArea())
                .toolbar { toolbarContent }
                .toolbarBackground(Theme.paper, for: .navigationBar)
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .preferredColorScheme(settings.appearance.colorScheme)
        .sheet(isPresented: $isInspectorPresented) {
            InspectorSheet(session: session)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsScreen()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isAboutPresented) {
            AboutScreen()
        }
        .fileImporter(isPresented: $isImporterPresented,
                      allowedContentTypes: Self.importTypes) { result in
            if case .success(let url) = result, let pane = importTarget {
                session.importFile(at: url, into: pane)
            }
            importTarget = nil
        }
        .alert("Can't compare this",
               isPresented: Binding(
                   get: { session.ingestionNotice != nil },
                   set: { if !$0 { session.ingestionNotice = nil } }),
               presenting: session.ingestionNotice) { _ in
            Button("OK", role: .cancel) {}
        } message: { notice in
            Text(notice.message)
        }
        .onChange(of: session.publishCount) {
            currentChange = 0
        }
    }

    // MARK: - header: panes, banner, chips, notices (sdd §7.3)

    @ViewBuilder
    private func header(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            panes
                .accessibilitySortPriority(1)
            if session.showsProgress {
                ThinProgressBar()
            }
            if let report = session.report {
                VerdictBanner(
                    verdict: report.verdict,
                    revealActive: session.revealFormatting,
                    onJumpToFirstChange: { jump(to: 1, proxy: proxy) },
                    onToggleReveal: { session.revealFormatting.toggle() })
                    .accessibilitySortPriority(3)
                chipRow(report)
                if report.document.isDegraded, let reason = report.document.degradationReason {
                    degradationNotice(reason)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var panes: some View {
        let cardA = PaneCard(pane: .a, session: session,
                             hintEmphasized: session.textA.isEmpty && !session.textB.isEmpty,
                             onRequestImport: requestImport)
        let cardB = PaneCard(pane: .b, session: session,
                             hintEmphasized: session.textB.isEmpty && !session.textA.isEmpty,
                             onRequestImport: requestImport)
        if isWide {
            HStack(alignment: .top, spacing: 10) {
                cardA
                cardB
            }
        } else {
            VStack(spacing: 8) {
                cardA
                cardB
            }
        }
    }

    private func chipRow(_ report: DiffReport) -> some View {
        HStack(spacing: 8) {
            Button {
                isProfilePresented = true
            } label: {
                HStack(spacing: 4) {
                    Text("\(report.profile.profile.rawValue.capitalized) · \(report.profile.isAutomatic ? "auto" : "manual")")
                        .font(.caption)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Content profile: \(report.profile.profile.rawValue), \(report.profile.isAutomatic ? "detected automatically" : "manual override")")
            .popover(isPresented: $isProfilePresented, arrowEdge: .top) {
                ProfileInfoView(session: session, detected: report.profile)
                    .presentationCompactAdaptation(.popover)
            }
            if report.profile.isIndentationSensitive {
                Text("indentation significant")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if session.clearBackup != nil {
                Button("Undo clear") { session.undoClear() }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private func degradationNotice(_ reason: DegradationReason) -> some View {
        let text: String
        switch reason {
        case .softThreshold:
            text = "Large input — details reduced to whole paragraphs and lines."
        case .inputTooLarge:
            text = "Input exceeds the 4 MB cap — showing a coarse comparison."
        case .pathologicalInput:
            text = "Mostly rewritten — showing a block-level result."
        }
        return Label(text, systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: - result area (sdd §7.3, §7.4)

    @ViewBuilder
    private var resultArea: some View {
        if !session.hasAnyInput {
            emptyState
        } else if let report = session.report, let viewModel = session.viewModel {
            if case .identical = report.verdict {
                // the banner is the result; no empty diff view (sdd §7.3)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    diffContent(report: report, viewModel: viewModel)
                        .opacity(session.showsProgress ? 0.55 : 1)
                }
                .accessibilitySortPriority(2)
            }
        } else {
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func diffContent(report: DiffReport, viewModel: DiffViewModel) -> some View {
        let styler = PieceStyler(accessiblePalette: settings.accessiblePalette,
                                 revealFormatting: session.revealFormatting)
        switch viewModel.content {
        case .prose(let blocks):
            ProseDiffView(blocks: blocks,
                          presentation: presentation,
                          changeTotal: viewModel.changes.count,
                          styler: styler,
                          fontScale: settings.fontScale)
        case .lines(let rows, let pairs):
            CodeDiffView(rows: rows,
                         pairs: pairs,
                         presentation: presentation,
                         changeTotal: viewModel.changes.count,
                         styler: styler,
                         fontScale: settings.fontScale,
                         useMonospaced: report.profile.profile == .code ? settings.codeMonospaced : false)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Paste two texts.\nRift tells you what actually changed.")
                .font(.title3)
                .fontDesign(.serif)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Try an example") {
                session.loadSample()
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .fontDesign(.serif)
            if session.clearBackup != nil {
                Button("Undo clear") { session.undoClear() }
                    .font(.footnote)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    // MARK: - toolbar (sdd §7.2)

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                isAboutPresented = true
            } label: {
                Text("Rift")
                    .font(.title3.weight(.semibold))
                    .fontDesign(.serif)
                    .foregroundStyle(.primary)
            }
            .accessibilityLabel("About Rift")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                session.swapSides()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
            }
            .disabled(!session.hasAnyInput)
            .accessibilityLabel("Swap sides")

            Button {
                presentationOverride = presentation == .unified ? .sideBySide : .unified
            } label: {
                Image(systemName: presentation == .unified
                      ? "rectangle.split.2x1" : "rectangle.grid.1x2")
            }
            .disabled(session.report == nil)
            .accessibilityLabel(presentation == .unified
                                ? "Switch to side-by-side" : "Switch to unified")

            Button {
                isInspectorPresented = true
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .accessibilityLabel("Inspector")

            Menu {
                if let report = session.report {
                    ShareLink(item: Export.summary(report: report,
                                                   a: session.textA, b: session.textB,
                                                   countsA: session.countsA,
                                                   countsB: session.countsB,
                                                   modeChoice: session.modeChoice)) {
                        Label("Share summary", systemImage: "doc.plaintext")
                    }
                    ShareLink(item: PatchExport(a: session.textA, b: session.textB,
                                                document: report.document),
                              preview: SharePreview("rift-comparison.patch")) {
                        Label("Export .patch", systemImage: "doc.badge.gearshape")
                    }
                    Divider()
                }
                Button {
                    isSettingsPresented = true
                } label: {
                    Label("Viewing options", systemImage: "textformat.size")
                }
                Button {
                    isAboutPresented = true
                } label: {
                    Label("About Rift", systemImage: "info.circle")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More")
        }
    }

    // MARK: - navigation (fr-9)

    private func requestImport(_ pane: PaneID) {
        importTarget = pane
        isImporterPresented = true
    }

    private func navigate(by delta: Int, proxy: ScrollViewProxy) {
        let total = changeAnchors.count
        guard total > 0 else { return }
        let next = min(max(currentChange + delta, 1), total)
        jump(to: next, proxy: proxy)
    }

    private func jump(to ordinal: Int, proxy: ScrollViewProxy) {
        guard ordinal >= 1, ordinal <= changeAnchors.count else { return }
        currentChange = ordinal
        withAnimation(nil) {
            proxy.scrollTo(DiffViewModel.anchorID(changeAnchors[ordinal - 1].hunkIndex),
                           anchor: .top)
        }
    }
}

/// the thin indeterminate bar for runs over 150 ms (sdd §7.3); uikit has no
/// indeterminate linear progress view, so this is a two-point slide — the one
/// functional animation in the app
struct ThinProgressBar: View {
    @State private var slid = false

    var body: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: max(geometry.size.width * 0.3, 24), height: 2)
                .offset(x: slid ? geometry.size.width * 0.7 : 0)
        }
        .frame(height: 2)
        .clipped()
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                slid = true
            }
        }
        .accessibilityLabel("Comparing")
    }
}

/// profile chip popover (fr-4, sdd §3.3): the detector's one-line explanation
/// plus the override picker; automation stays inspectable
struct ProfileInfoView: View {
    @Bindable var session: CompareSession
    let detected: DetectedProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(detected.explanation)
                .font(.footnote)
                .fontDesign(.serif)
                .fixedSize(horizontal: false, vertical: true)
            if detected.isAutomatic {
                Text("Confidence \(Int((detected.confidence * 100).rounded())) %")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if detected.isIndentationSensitive {
                Text("Indentation looks meaning-bearing, so layout rules keep it significant.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider().overlay(Theme.hairline)
            Picker("Profile", selection: $session.profileOverride) {
                Text("Automatic").tag(Profile?.none)
                ForEach(Profile.allCases, id: \.self) { profile in
                    Text(profile.rawValue.capitalized).tag(Profile?.some(profile))
                }
            }
            .pickerStyle(.menu)
        }
        .padding(14)
        .frame(idealWidth: 300)
        .presentationBackground(Theme.paper)
    }
}

#Preview {
    CompareScreen()
}
