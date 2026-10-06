import RiftEngine
import SwiftUI
import UniformTypeIdentifiers

/// source acquisition and verdict-first reading share one session. switching
/// workspaces never computes, clears sources or resets result view choices
struct CompareScreen: View {
    private enum Workspace: String, CaseIterable {
        case sources = "Sources"
        case comparison = "Comparison"
    }

    @State private var workspace: Workspace = .sources
    @State private var expandedPane: PaneID? = .a
    @FocusState private var focusedPane: PaneID?
    @State private var session = CompareSession()
    @State private var sourceViewportSize: CGSize = .zero
    private var settings = ViewerSettings()

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @ScaledMetric(relativeTo: .body) private var proseUnit: CGFloat = Theme.proseBaseSize

    @State private var isInspectorPresented = false
    @State private var isSettingsPresented = false
    @State private var isAboutPresented = false
    @State private var isProfilePresented = false
    @State private var isLayoutPresented = false
    @State private var isImporterPresented = false
    @State private var importTarget: PaneID?

    // MARK: - per-comparison view state (m3.3a): reset only when both sources are empty

    @State private var layoutChoice: LayoutChoice = .automatic
    @State private var selection = ChangeSelection()
    /// the evidence width after the safe area and the evidence padding: the
    /// scroll content's width less the 16-point padding on each side
    @State private var evidenceWidth: CGFloat = 0

    private static let importTypes: [UTType] = [
        .plainText, .text, .sourceCode, .json, .xml, .yaml, .commaSeparatedText, .log,
    ]

    /// horizontal padding of the evidence, on each side (ProseDiffView)
    private static let evidencePadding: CGFloat = 16

    // MARK: - layout defaults (sdd §7.2, fr-7)

    /// the effective type size over its base, times the viewer font scale
    private var typeScale: Double {
        Double(proseUnit / Theme.proseBaseSize) * settings.fontScale
    }

    private var twoColumnsFit: Bool {
        ColumnFit.twoColumnsFit(contentWidth: Double(evidenceWidth), typeScale: typeScale)
    }

    /// the rendered geometry: the explicit choice as chosen, automatic by width
    private var presentation: DiffPresentation {
        layoutChoice.resolvePresentation(twoColumnsFit: twoColumnsFit)
    }

    private var changeAnchors: [ChangeAnchor] {
        session.viewModel?.changes ?? []
    }

    /// a result view exists to lay out: a report that is not merely identical
    private var hasResultContent: Bool {
        guard let report = session.report else { return false }
        if case .identical = report.verdict { return false }
        return true
    }

    private var scrollsSourceChrome: Bool {
        dynamicTypeSize.isAccessibilitySize || verticalSizeClass == .compact
    }

    private var hasCompactEditorFocus: Bool {
        workspace == .sources && focusedPane != nil && verticalSizeClass == .compact
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if workspace == .comparison || !scrollsSourceChrome {
                    workspacePicker
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }

                // both scroll surfaces stay mounted, preserving editor and
                // result expansion state while the inactive surface is hidden
                ZStack {
                    sourcesArea
                        .zIndex(workspace == .sources ? 1 : 0)
                        .frame(height: workspace == .sources ? nil : 0)
                        .clipped()
                        .opacity(workspace == .sources ? 1 : 0)
                        .allowsHitTesting(workspace == .sources)
                        .accessibilityHidden(workspace != .sources)
                    comparisonArea
                        .zIndex(workspace == .comparison ? 1 : 0)
                        .frame(height: workspace == .comparison ? nil : 0)
                        .clipped()
                        .opacity(workspace == .comparison ? 1 : 0)
                        .allowsHitTesting(workspace == .comparison)
                        .accessibilityHidden(workspace != .comparison)
                }
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if workspace == .sources && !scrollsSourceChrome && focusedPane == nil {
                    sourceFooter
                }
            }
            .toolbar { toolbarContent }
            .toolbarBackground(Theme.paper, for: .navigationBar)
            .toolbar {
                if !hasCompactEditorFocus {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { focusedPane = nil }
                    }
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
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
        .onChange(of: workspace) {
            if workspace == .comparison { focusedPane = nil }
        }
        .onChange(of: session.publishCount) {
            // a recomputation keeps the selection, clamped to the new total.
            // one-sided states publish too, with a nil report, and must not
            // touch it (m3.3a)
            guard session.report != nil else { return }
            selection.clamp(total: changeAnchors.count)
        }
        .onChange(of: session.hasAnyInput) {
            if !session.hasAnyInput {
                resetPerComparisonState()
            }
        }
    }

    /// the comparison boundary (m3.3a): both sources empty resets every
    /// per-comparison view choice; nothing else does
    private func resetPerComparisonState() {
        layoutChoice = .automatic
        selection.reset()
        session.revealFormatting = false
    }

    // MARK: - source acquisition

    private var workspacePicker: some View {
        Picker("Workspace", selection: $workspace) {
            ForEach(Workspace.allCases, id: \.self) { item in
                Text(item.rawValue).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }

    private var sourcesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // scroll navigation and options with the content when fixed
                    // chrome would leave too little space for the active editor
                    if scrollsSourceChrome {
                        workspacePicker
                    }
                    panes
                    Text(session.isResultCurrent ? "Comparison ready. Your texts stay editable." :
                            (hasBothInputs ? "Updating comparison…" : "Add both texts. The comparison updates automatically."))
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                    if hasBothInputs {
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                workspace = .comparison
                            } label: {
                                HStack {
                                    Text("View comparison")
                                    Spacer(minLength: 8)
                                    Image(systemName: "arrow.right")
                                }
                                .font(.body.weight(.medium))
                                .frame(maxWidth: .infinity, minHeight: 28)
                            }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.roundedRectangle(radius: 12))
                            .controlSize(.regular)
                            .tint(Color(uiColor: Theme.actionUIColor))
                            .foregroundStyle(Color(uiColor: Theme.actionLabelUIColor))
                            .disabled(!hasBothInputs)
                        }
                    } else if !session.hasAnyInput {
                        TextAction(title: "Load sample", font: .subheadline, color: Theme.inkSecondary,
                                   horizontalPadding: 0, alignment: .leading) { session.loadSample() }
                    }
                    if scrollsSourceChrome && focusedPane == nil {
                        sourceOptions
                            .padding(.top, 8)
                            .overlay(alignment: .top) {
                                Rectangle().fill(Theme.fieldEdge).frame(height: 0.5)
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: focusedPane) {
                if let pane = focusedPane { proxy.scrollTo(pane, anchor: .top) }
            }
            .onGeometryChange(for: CGSize.self) { geometry in
                geometry.size
            } action: { size in
                let previousSize = sourceViewportSize
                sourceViewportSize = size
                // leave an expanding viewport alone during keyboard dismissal
                if workspace == .sources, let pane = focusedPane,
                   size.height < previousSize.height || size.width != previousSize.width {
                    proxy.scrollTo(pane, anchor: .top)
                }
            }
            .onChange(of: dynamicTypeSize) {
                if workspace == .sources, let pane = focusedPane {
                    proxy.scrollTo(pane, anchor: .top)
                }
            }
        }
    }

    private var hasBothInputs: Bool {
        !session.textA.isEmpty && !session.textB.isEmpty
    }

    private var panes: some View {
        VStack(spacing: 0) {
            PaneCard(pane: .a, session: session, onRequestImport: requestImport,
                     focus: $focusedPane, isExpanded: expandedPane == .a,
                     editingViewportHeight: sourceViewportSize.height,
                     onSelect: { selectSource(.a) })
            Rectangle()
                .fill(Theme.fieldEdge)
                .frame(height: 0.5)
                .padding(.horizontal, 16)
                .accessibilityHidden(true)
            PaneCard(pane: .b, session: session, onRequestImport: requestImport,
                     focus: $focusedPane, isExpanded: expandedPane == .b,
                     editingViewportHeight: sourceViewportSize.height,
                     onSelect: { selectSource(.b) })
        }
        .background(Theme.field)
        .clipShape(RoundedRectangle(cornerRadius: Theme.sourceGroupRadius, style: .continuous))
    }

    private func selectSource(_ pane: PaneID) {
        focusedPane = nil
        expandedPane = expandedPane == pane ? nil : pane
    }

    private var sourceFooter: some View {
        sourceOptions
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(Theme.paper)
            .overlay(alignment: .top) { Rectangle().fill(Theme.fieldEdge).frame(height: 0.5) }
    }

    private var sourceOptions: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(spacing: 16))
        return layout {
            Button {
                isInspectorPresented = true
            } label: {
                HStack(spacing: 6) {
                    Text("\(session.modeChoice.label) comparison")
                    Image(systemName: "chevron.down").font(.caption)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Comparison: \(session.modeChoice.label)")
            .accessibilityHint("Opens comparison options")
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            Button {
                isSettingsPresented = true
            } label: {
                Label("View", systemImage: "slider.horizontal.3")
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Viewing options")
        }
        .font(.subheadline)
        .buttonStyle(.plain)
    }

    // MARK: - comparison reading

    private var comparisonArea: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .topLeading) {
                ScrollView {
                    VStack(spacing: 0) {
                        if let report = session.report {
                            resultHeader(report, proxy: proxy)
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                        }
                        resultArea
                    }
                    .frame(maxWidth: .infinity)
                    .opacity(session.isResultCurrent ? 1 : 0)
                    .allowsHitTesting(session.isResultCurrent)
                    .accessibilityHidden(!session.isResultCurrent)
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.width
                    } action: { width in
                        evidenceWidth = max(0, width - 2 * Self.evidencePadding)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if selection.isVisible, session.isResultCurrent {
                        ChangeNavigator(
                            selection: selection,
                            onPrevious: { navigate(by: -1, proxy: proxy) },
                            onNext: { navigate(by: 1, proxy: proxy) })
                    }
                }
                // pending feedback belongs to the viewport, so a retained
                // deep evidence scroll position cannot hide the status
                if !session.isResultCurrent { pendingComparison }
            }
        }
    }

    private var pendingComparison: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(hasBothInputs ? "Updating comparison…" : "Add both texts to compare.")
                .font(.headline)
            if session.showsProgress { ThinProgressBar() }
            TextAction(title: "Edit sources", font: .body, horizontalPadding: 0,
                       alignment: .leading) { workspace = .sources }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .accessibilityElement(children: .contain)
    }

    private var sourceIdentity: some View {
        VStack(alignment: .leading, spacing: 4) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    sourceDirection
                    editSourcesAction
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    sourceDirection
                    Spacer(minLength: 8)
                    editSourcesAction
                }
            }
            ForEach([PaneID.a, .b], id: \.self) { pane in
                let meta = session.meta(for: pane)
                if let source = meta.sourceLabel {
                    Text("\(pane == .a ? "Original" : "Revision"): \(source)")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let decoded = meta.decodedAs {
                    Label("\(pane == .a ? "Original" : "Revision") decoded as \(decoded)",
                          systemImage: "info.circle")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var sourceDirection: some View {
        Text("Original → Revision")
            .font(.subheadline.weight(.medium))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var editSourcesAction: some View {
        TextAction(title: "Edit sources", font: .subheadline, horizontalPadding: 0,
                   alignment: .leading) { workspace = .sources }
    }

    /// the verdict, its notation line, the three controls, then the structural
    /// rule that separates the statement from its evidence (m3.3a: no eyebrow)
    @ViewBuilder
    private func resultHeader(_ report: DiffReport, proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VerdictBanner(
                verdict: report.verdict,
                revealActive: session.revealFormatting,
                onJumpToFirstChange: { jump(to: 1, proxy: proxy) },
                onToggleReveal: { session.revealFormatting.toggle() })
                .accessibilitySortPriority(3)
            sourceIdentity
                .accessibilitySortPriority(2.7)
            metaLine(report)
                .accessibilitySortPriority(2.5)
            if report.document.isDegraded, let reason = report.document.degradationReason {
                degradationNotice(reason)
            }
            RuleLine()
        }
    }

    // MARK: - the three header controls (m3.3a): content, comparison, layout

    /// one row when the controls fit (layout at the trailing edge), otherwise
    /// as many rows as needed in order (content and comparison, then layout),
    /// one control per row at accessibility sizes; nothing is abbreviated or
    /// hidden. ControlRows places each control exactly once, so each keeps
    /// its own popover
    private func metaLine(_ report: DiffReport) -> some View {
        ControlRows(onePerRow: dynamicTypeSize.isAccessibilitySize,
                    trailingLast: hasResultContent) {
            contentControl(report)
            comparisonLink
            if hasResultContent {
                layoutControl
            }
        }
    }

    /// `Content: Prose ▾` opens the detector's explanation and the override
    /// (fr-4); `· chosen` marks a manual override
    private func contentControl(_ report: DiffReport) -> some View {
        Button {
            isProfilePresented = true
        } label: {
            headerControl(prefix: "Content:", value: contentValue(report), glyph: "chevron.down")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Content profile: \(report.profile.profile.rawValue), \(report.profile.isAutomatic ? "detected automatically" : "manual override")")
        .accessibilityHint("Shows the detection explanation and the profile override")
        .popover(isPresented: $isProfilePresented, arrowEdge: .top) {
            ProfileInfoView(session: session, detected: report.profile)
                .presentationCompactAdaptation(.popover)
        }
    }

    private func contentValue(_ report: DiffReport) -> String {
        let name = report.profile.profile.rawValue.capitalized
        return report.profile.isAutomatic ? name : "\(name) · chosen"
    }

    /// `Comparison: Smart ›` names the mode in every result state, smart
    /// included, and opens the inspector where it is set (fr-5)
    private var comparisonLink: some View {
        Button {
            isInspectorPresented = true
        } label: {
            headerControl(prefix: "Comparison:", value: session.modeChoice.label, glyph: "chevron.right")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Comparison: \(session.modeChoice.label.lowercased())")
        .accessibilityHint("Opens the Inspector")
    }

    /// `Layout: Automatic ▾` opens the chooser (fr-7): a popover, like the
    /// content profile's, so the three descriptions are visible rather than
    /// left to a menu's accessibility hints
    private var layoutControl: some View {
        Button {
            isLayoutPresented = true
        } label: {
            headerControl(prefix: "Layout:", value: layoutChoice.menuTitle, glyph: "chevron.down")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Layout options")
        .accessibilityValue(layoutChoice.accessibilityValue(effective: presentation))
        .accessibilityHint("Chooses how the result is laid out")
        .popover(isPresented: $isLayoutPresented) {
            LayoutChooserView(choice: $layoutChoice)
                .presentationCompactAdaptation(.popover)
        }
    }

    /// a header control: a quiet prefix, the value in ink, and a small glyph
    /// that says what it opens (chevron.down: a menu or popover; chevron.right:
    /// another screen), laid out in a genuine 44-point frame (nfr-5)
    private func headerControl(prefix: String, value: String, glyph: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if dynamicTypeSize.isAccessibilitySize {
                Text("\(prefix) \(value)")
                    .foregroundStyle(Theme.ink)
            } else {
                Text(prefix)
                    .foregroundStyle(Theme.inkSecondary)
                Text(value)
                    .foregroundStyle(Theme.ink)
            }
            Image(systemName: glyph)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
        }
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func degradationNotice(_ reason: DegradationReason) -> some View {
        let text: String
        switch reason {
        case .softThreshold:
            text = "Large input: detail reduced to whole paragraphs and lines."
        case .inputTooLarge:
            text = "Input exceeds the 4 MB cap: coarse comparison."
        case .pathologicalInput:
            text = "Mostly rewritten: block-level result."
        }
        return Label(text, systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: - result area (sdd §7.3, §7.4)

    /// what follows the header inside the one scroll: the empty-area
    /// instruction, the diff content, or nothing (identical, or one side only)
    @ViewBuilder
    private var resultArea: some View {
        if !session.hasAnyInput {
            EmptyView()
        } else if let report = session.report, let viewModel = session.viewModel {
            if case .identical = report.verdict {
                // the statement is the result; no empty diff view (sdd §7.3)
                EmptyView()
            } else {
                diffContent(report: report, viewModel: viewModel)
                    .opacity(session.showsProgress ? 0.55 : 1)
                    .accessibilitySortPriority(2)
            }
        } else {
            // one side filled: the empty field's placeholder carries the
            // instruction and its own undo, so the area stays quiet (sdd §7.3)
            EmptyView()
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

    // MARK: - toolbar (sdd §7.2): global actions only. swap exists only once
    // there is something to swap; comparison options remain in the footer,
    // result header and More menu

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if hasCompactEditorFocus {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { focusedPane = nil }
            }
        } else {
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarLeading) { BrandMark() }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarLeading) { BrandMark() }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if session.hasAnyInput {
                    Button {
                        session.swapSides()
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                    }
                    .accessibilityLabel("Swap sides")
                }

                Menu {
                    if session.isResultCurrent, let report = session.report {
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
                        isInspectorPresented = true
                    } label: {
                        Label("Comparison options", systemImage: "slider.horizontal.3")
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
    }

    // MARK: - navigation (fr-9)

    private func requestImport(_ pane: PaneID) {
        focusedPane = nil
        importTarget = pane
        isImporterPresented = true
    }

    /// previous / next from the navigator: the selection moves first, so the
    /// label and the arrows can never disagree; the announcement names the
    /// new selection for voiceover
    private func navigate(by delta: Int, proxy: ScrollViewProxy) {
        let target = delta > 0 ? selection.next() : selection.previous()
        guard let target else { return }
        scroll(to: target, proxy: proxy)
        AccessibilityNotification.Announcement(selection.label).post()
    }

    /// the verdict tap: selects and scrolls to the given ordinal
    private func jump(to ordinal: Int, proxy: ScrollViewProxy) {
        guard selection.jump(to: ordinal) else { return }
        scroll(to: ordinal, proxy: proxy)
        AccessibilityNotification.Announcement(selection.label).post()
    }

    private func scroll(to ordinal: Int, proxy: ScrollViewProxy) {
        guard ordinal >= 1, ordinal <= changeAnchors.count else { return }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Theme.ink.opacity(0.45))
                .frame(width: max(geometry.size.width * 0.3, 24), height: 2)
                .offset(x: slid ? geometry.size.width * 0.7 : 0)
        }
        .frame(height: 2)
        .clipped()
        .task(id: reduceMotion) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { slid = false }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                slid = true
            }
        }
        .accessibilityLabel("Comparing")
    }
}

/// profile popover (fr-4, sdd §3.3): the detector's one-line explanation plus
/// the override picker; automation stays inspectable
struct ProfileInfoView: View {
    @Bindable var session: CompareSession
    let detected: DetectedProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if session.isResultCurrent {
                Text(detected.explanation)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                if detected.isAutomatic {
                    Text("CONFIDENCE \(Int((detected.confidence * 100).rounded())) %")
                        .font(Theme.data)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Confidence \(Int((detected.confidence * 100).rounded())) percent")
                }
                if detected.isIndentationSensitive {
                    Text("Indentation looks meaning-bearing, so layout rules keep it significant.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Updating comparison…")
                    .font(.footnote)
            }
            RuleLine()
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
        .tint(Theme.accent)
        .presentationBackground(Theme.paper)
    }
}

/// rows of header controls (m3.3a): as many controls per row as fit, in
/// order, each measured at its ideal width so nothing truncates; when every
/// control fits on one row and `trailingLast` is set, the last control (the
/// layout control) is pushed to the trailing edge; `onePerRow` gives every
/// control its own row and lets its text wrap (accessibility sizes). each
/// control is placed exactly once, so its popover stays attached to it
struct ControlRows: Layout {
    var spacing: CGFloat = 14
    var rowSpacing: CGFloat = 4
    var onePerRow = false
    var trailingLast = false

    /// one placed control: its index, the proposal it was measured with (the
    /// same one it is placed with) and the size that produced
    private struct Cell {
        let index: Int
        let proposal: ProposedViewSize
        let size: CGSize
    }

    private struct Row {
        var cells: [Cell] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// the rows for a given width. a control is measured at its ideal width;
    /// one wider than the row, or every control at accessibility sizes, is
    /// measured at the row width so its text wraps instead of overflowing.
    /// once a break has happened every later control starts its own row, so
    /// the outcomes are exactly: one row; content and comparison, then
    /// layout; one control per row
    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (index, subview) in subviews.enumerated() {
            var proposal: ProposedViewSize = onePerRow ? ProposedViewSize(width: width, height: nil) : .unspecified
            var size = subview.sizeThatFits(proposal)
            if !onePerRow, size.width > width {
                proposal = ProposedViewSize(width: width, height: nil)
                size = subview.sizeThatFits(proposal)
            }
            let extended = row.cells.isEmpty ? size.width : row.width + spacing + size.width
            if !row.cells.isEmpty, onePerRow || !rows.isEmpty || extended > width {
                rows.append(row)
                row = Row()
            }
            row.width = row.cells.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.cells.append(Cell(index: index, proposal: proposal, size: size))
        }
        if !row.cells.isEmpty {
            rows.append(row)
        }
        return rows
    }

    private func availableWidth(_ proposal: ProposedViewSize) -> CGFloat {
        guard let width = proposal.width, width.isFinite else { return .greatestFiniteMagnitude }
        return width
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = availableWidth(proposal)
        let rows = rows(width: width, subviews: subviews)
        let height = rows.reduce(CGFloat(0)) { $0 + $1.height }
            + rowSpacing * CGFloat(max(rows.count - 1, 0))
        let widest = rows.reduce(CGFloat(0)) { max($0, $1.width) }
        return CGSize(width: width < .greatestFiniteMagnitude ? width : widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for (position, cell) in row.cells.enumerated() {
                let isTrailing = trailingLast && rows.count == 1 && subviews.count > 1
                    && position == row.cells.count - 1
                let originX = isTrailing ? bounds.maxX - cell.size.width : x
                subviews[cell.index].place(
                    at: CGPoint(x: originX, y: y + (row.height - cell.size.height) / 2),
                    anchor: .topLeading, proposal: cell.proposal)
                x += cell.size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }
}

/// the layout chooser (fr-7, m3.3a): three rows, each a title, its one-line
/// description and a checkmark on the current choice, divided by hairlines.
/// a popover like the content profile's, so the descriptions stay visible
struct LayoutChooserView: View {
    @Binding var choice: LayoutChoice
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(LayoutChoice.allCases.enumerated()), id: \.element) { index, option in
                if index > 0 {
                    RuleLine()
                }
                Button {
                    choice = option
                    dismiss()
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.menuTitle)
                                .font(.subheadline)
                                .foregroundStyle(Theme.ink)
                            Text(option.menuDescription)
                                .font(.footnote)
                                .foregroundStyle(Theme.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .opacity(option == choice ? 1 : 0)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.menuTitle)
                .accessibilityHint(option.menuDescription)
                .accessibilityAddTraits(option == choice ? .isSelected : [])
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .frame(idealWidth: 300)
        .tint(Theme.accent)
        .presentationBackground(Theme.paper)
    }
}

#Preview {
    CompareScreen()
}
