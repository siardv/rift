/// pure presentation state of the result area (m3.3a): the user-facing layout
/// choice and the geometry it resolves to, the width rule for two columns, and
/// the change selection behind the navigator (fr-7, fr-9). no ui, no
/// observation, no foundation: the file is compiled into RiftTests as source
/// (see project.yml), in the pattern of ClearUndoLedger.swift

/// which result geometry is rendered (fr-7); implementation vocabulary, never
/// shown to the user
enum DiffPresentation: String, Hashable, Sendable {
    case unified
    case sideBySide
    /// original and revision as stacked pairs: the paired reading where two
    /// columns do not fit (m3.3a)
    case stackedPairs
}

/// the user-facing layout choice (m3.3a). automatic picks by width; the two
/// explicit choices are always rendered as chosen, so a choice never lies
enum LayoutChoice: String, CaseIterable, Hashable, Sendable {
    case automatic
    case inline
    case paired

    var menuTitle: String {
        switch self {
        case .automatic: return "Automatic"
        case .inline: return "Inline"
        case .paired: return "Paired"
        }
    }

    /// the one-line description shown beside the title in the chooser
    var menuDescription: String {
        switch self {
        case .automatic: return "Chooses the best layout for this screen."
        case .inline: return "Shows changes in one reading flow."
        case .paired: return "Keeps original and revision separate."
        }
    }

    /// the geometry this choice renders when two columns do or do not fit
    func resolvePresentation(twoColumnsFit: Bool) -> DiffPresentation {
        switch self {
        case .automatic: return twoColumnsFit ? .sideBySide : .unified
        case .inline: return .unified
        case .paired: return twoColumnsFit ? .sideBySide : .stackedPairs
        }
    }

    /// voiceover value of the layout control: the choice, and what automatic
    /// resolved to
    func accessibilityValue(effective: DiffPresentation) -> String {
        switch self {
        case .automatic:
            return "automatic, currently \(effective == .sideBySide ? "paired" : "inline")"
        case .inline:
            return "inline"
        case .paired:
            return effective == .sideBySide ? "paired, columns" : "paired, stacked"
        }
    }
}

/// the width rule for two columns (m3.3a): each column keeps a physical
/// minimum of 320 points, scaled up with the effective type size and never
/// down, so a reduced viewer font scale cannot make undersized columns eligible
enum ColumnFit {
    /// the physical minimum of one column, in points
    static let minimumColumnWidth: Double = 320
    /// what prose spends between the columns: two hstack gaps of 6 points
    /// and the half-point hairline; the code grid uses less
    static let columnGap: Double = 12.5

    /// `contentWidth` is the evidence width after the safe area and the
    /// evidence padding are removed; `typeScale` is the scaled prose size over
    /// its base, times the viewer font scale
    static func twoColumnsFit(contentWidth: Double, typeScale: Double) -> Bool {
        (contentWidth - columnGap) / 2 >= minimumColumnWidth * max(typeScale, 1)
    }
}

/// the change selection behind the navigator (fr-9, m3.3a): nothing is
/// selected until the user navigates or taps the verdict, and the label never
/// contradicts the arrows. `current` is 1-based
struct ChangeSelection: Equatable, Sendable {
    private(set) var total: Int
    private(set) var current: Int?

    init(total: Int = 0, current: Int? = nil) {
        self.total = max(0, total)
        self.current = nil
        if let current, current >= 1, current <= self.total {
            self.current = current
        }
    }

    /// the navigator exists only with two or more changes
    var isVisible: Bool {
        total >= 2
    }

    var canGoPrevious: Bool {
        (current ?? 0) > 1
    }

    var canGoNext: Bool {
        (current ?? 0) < total
    }

    /// `2 changes` before any selection, `Change 1 of 2` after one
    var label: String {
        if let current {
            return "Change \(current) of \(total)"
        }
        return total == 1 ? "1 change" : "\(total) changes"
    }

    /// selects the next change; nil when there is none
    @discardableResult
    mutating func next() -> Int? {
        guard canGoNext else { return nil }
        let target = (current ?? 0) + 1
        current = target
        return target
    }

    /// selects the previous change; nil when there is none
    @discardableResult
    mutating func previous() -> Int? {
        guard canGoPrevious, let current else { return nil }
        let target = current - 1
        self.current = target
        return target
    }

    /// selects an ordinal directly (the verdict tap selects 1)
    @discardableResult
    mutating func jump(to ordinal: Int) -> Bool {
        guard ordinal >= 1, ordinal <= total else { return false }
        current = ordinal
        return true
    }

    /// a recomputation keeps the selection, clamped to the new total; no
    /// changes at all leaves nothing selected
    mutating func clamp(total newTotal: Int) {
        total = max(0, newTotal)
        if let current {
            self.current = total >= 1 ? min(current, total) : nil
        }
    }

    /// the comparison boundary: nothing selected, nothing to count
    mutating func reset() {
        total = 0
        current = nil
    }
}
