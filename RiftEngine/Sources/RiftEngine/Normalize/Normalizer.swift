import Foundation

/// normalization and provenance (sdd §3.2, §6.3). every function here mirrors
/// the golden-corpus reference implementation: rule order, constants, and
/// encodings are a contract, not an implementation detail.
enum Normalizer {
    /// invisible format characters stripped at l1: bom/zwnbsp, zero-width space,
    /// word joiner, soft hyphen. joiners (zwj/zwnj) are deliberately NOT here:
    /// they carry meaning in emoji and several scripts (sdd §1.5: explainable rules)
    static let invisibles: Set<Unicode.Scalar> = ["\u{FEFF}", "\u{200B}", "\u{2060}", "\u{00AD}"]

    /// typographic equivalence at l2, prose only (sdd §3.2)
    static let typographic: [Unicode.Scalar: String] = [
        "\u{2018}": "'", "\u{2019}": "'", "\u{201A}": "'", "\u{201B}": "'",
        "\u{201C}": "\"", "\u{201D}": "\"", "\u{201E}": "\"", "\u{201F}": "\"",
        "\u{2012}": "-", "\u{2013}": "-", "\u{2014}": "-", "\u{2015}": "-",
        "\u{2026}": "...",
    ]

    static let nbsp: Unicode.Scalar = "\u{00A0}"

    struct ScalarItem {
        let scalar: Unicode.Scalar
        let start: Int  // utf-8 byte offset in the original
        let end: Int
    }

    struct RawLine {
        let content: [ScalarItem]
        let eol: String  // "\n", "\r\n", "\r", or "" for the final unterminated line
    }

    /// codepoint-exact string equality (the reference's `==`). swift's own
    /// String == uses canonical equivalence, which would blur l0/l1 and any
    /// custom pipeline with nfc disabled — so equality is always utf-8 bytes
    static func utf8Equal(_ x: String, _ y: String) -> Bool {
        x.utf8.count == y.utf8.count && x.utf8.elementsEqual(y.utf8)
    }

    static func utf8Width(_ scalar: Unicode.Scalar) -> Int {
        let v = scalar.value
        if v < 0x80 { return 1 }
        if v < 0x800 { return 2 }
        if v < 0x10000 { return 3 }
        return 4
    }

    static func scalarItems(_ s: String) -> [ScalarItem] {
        var out: [ScalarItem] = []
        out.reserveCapacity(s.unicodeScalars.count)
        var pos = 0
        for scalar in s.unicodeScalars {
            let w = utf8Width(scalar)
            out.append(ScalarItem(scalar: scalar, start: pos, end: pos + w))
            pos += w
        }
        return out
    }

    /// splits on \r\n, \n, \r only; a final empty segment after a terminal eol is
    /// dropped, which is what normalizes the eof newline structurally (l0 still
    /// sees the raw bytes)
    static func splitLines(_ items: [ScalarItem]) -> [RawLine] {
        var lines: [RawLine] = []
        var current: [ScalarItem] = []
        var i = 0
        let n = items.count
        while i < n {
            let v = items[i].scalar.value
            if v == 0x0D {
                var eol = "\r"
                var j = i + 1
                if j < n && items[j].scalar.value == 0x0A {
                    eol = "\r\n"
                    j += 1
                }
                lines.append(RawLine(content: current, eol: eol))
                current = []
                i = j
            } else if v == 0x0A {
                lines.append(RawLine(content: current, eol: "\n"))
                current = []
                i += 1
            } else {
                current.append(items[i])
                i += 1
            }
        }
        if !current.isEmpty {
            lines.append(RawLine(content: current, eol: ""))
        }
        return lines
    }

    private static func isSpaceOrTab(_ v: UInt32) -> Bool {
        v == 0x20 || v == 0x09
    }

    /// canonical text of one line at `level` for `profile`. order is pinned:
    /// per-scalar mapping (invisibles, nbsp, typographic) -> collapse runs
    /// (leading run preserved: indentation is an l3 concern) -> strip trailing
    /// space/tab -> nfc -> case/punctuation opt-ins
    static func canonLine(_ content: [ScalarItem], level: Int, profile: Profile, rules: RuleSet) -> String {
        var scalars: [Unicode.Scalar] = []
        scalars.reserveCapacity(content.count)
        for item in content {
            let sc = item.scalar
            if level >= 1 && rules.stripInvisibles && invisibles.contains(sc) {
                continue
            }
            if level >= 2 && rules.nbspToSpace && sc == nbsp {
                scalars.append(" ")
                continue
            }
            if level >= 2 && rules.typographicEquivalence && profile == .prose,
               let mapped = typographic[sc] {
                scalars.append(contentsOf: mapped.unicodeScalars)
                continue
            }
            scalars.append(sc)
        }
        if level >= 2 && rules.collapseSpaceRuns {
            var lead = 0
            while lead < scalars.count && isSpaceOrTab(scalars[lead].value) {
                lead += 1
            }
            var collapsed: [Unicode.Scalar] = Array(scalars[0..<lead])
            var inRun = false
            for sc in scalars[lead...] {
                if isSpaceOrTab(sc.value) {
                    if !inRun {
                        collapsed.append(" ")
                    }
                    inRun = true
                } else {
                    collapsed.append(sc)
                    inRun = false
                }
            }
            scalars = collapsed
        }
        if level >= 1 && rules.stripTrailingWhitespace {
            while let last = scalars.last, isSpaceOrTab(last.value) {
                scalars.removeLast()
            }
        }
        var text = String(String.UnicodeScalarView(scalars))
        if level >= 1 && rules.unicodeNFC {
            text = text.precomposedStringWithCanonicalMapping
        }
        if level >= 1 && rules.ignoreCase {
            text = text.lowercased()
        }
        if level >= 1 && rules.ignorePunctuation {
            let kept = text.unicodeScalars.filter { !isPunctuation($0) }
            text = String(String.UnicodeScalarView(kept))
        }
        return text
    }

    static func isPunctuation(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation,
             .closePunctuation, .initialPunctuation, .finalPunctuation,
             .otherPunctuation:
            return true
        default:
            return false
        }
    }

    /// which l3 semantics apply (sdd §3.3 + appendix a footnote)
    enum EffectiveL3 {
        case prose
        case code
        case plain
    }

    static func effectiveL3(profile: Profile, rules: RuleSet, sensitive: Bool) -> EffectiveL3 {
        if profile == .prose && rules.reflowProse {
            return .prose
        }
        if profile == .code && !sensitive {
            return .code
        }
        return .plain
    }

    private static func proseWords(of line: String) -> [String] {
        // split on spaces and tabs; a preserved leading indentation run must not
        // glue itself onto the first word
        var words: [String] = []
        var current: [Unicode.Scalar] = []
        for sc in line.unicodeScalars {
            if isSpaceOrTab(sc.value) {
                if !current.isEmpty {
                    words.append(String(String.UnicodeScalarView(current)))
                    current = []
                }
            } else {
                current.append(sc)
            }
        }
        if !current.isEmpty {
            words.append(String(String.UnicodeScalarView(current)))
        }
        return words
    }

    private static func stripLeadingSpacesTabs(_ line: String) -> String {
        var scalars = Array(line.unicodeScalars)
        var i = 0
        while i < scalars.count && isSpaceOrTab(scalars[i].value) {
            i += 1
        }
        scalars.removeFirst(i)
        return String(String.UnicodeScalarView(scalars))
    }

    /// canonical form of the whole text at `level` (equality is a comparison of
    /// these; sdd §6.4). l1/l2 use a line-terminated encoding so canonicalization
    /// is idempotent and a trailing blank line stays representable
    static func canonicalString(_ s: String, level: Int, profile: Profile,
                                rules: RuleSet, sensitive: Bool) -> String {
        if level == 0 {
            return s
        }
        let lines = splitLines(scalarItems(s))
        var texts = lines.map { canonLine($0.content, level: level, profile: profile, rules: rules) }
        if level >= 2 {
            if rules.collapseBlankLines {
                var collapsed: [String] = []
                var prevBlank = false
                for t in texts {
                    let blank = t.isEmpty
                    if blank && prevBlank {
                        continue
                    }
                    collapsed.append(t)
                    prevBlank = blank
                }
                texts = collapsed
            }
            if rules.trimOuterBlankLines {
                while let first = texts.first, first.isEmpty {
                    texts.removeFirst()
                }
                while let last = texts.last, last.isEmpty {
                    texts.removeLast()
                }
            }
        }
        if level < 3 {
            return texts.map { $0 + "\n" }.joined()
        }
        switch effectiveL3(profile: profile, rules: rules, sensitive: sensitive) {
        case .prose:
            var paragraphs: [String] = []
            var current: [String] = []
            for t in texts {
                if t.isEmpty {
                    if !current.isEmpty {
                        paragraphs.append(current.flatMap { proseWords(of: $0) }.joined(separator: " "))
                        current = []
                    }
                } else {
                    current.append(t)
                }
            }
            if !current.isEmpty {
                paragraphs.append(current.flatMap(proseWords(of:)).joined(separator: " "))
            }
            // paragraphs joined by a blank line so l3 canonicalization is idempotent
            return paragraphs.joined(separator: "\n\n")
        case .code:
            var out: [String] = []
            for t in texts {
                if t.isEmpty && rules.ignoreBlankLinesEntirely {
                    continue
                }
                out.append(rules.ignoreIndentation ? stripLeadingSpacesTabs(t) : t)
            }
            return out.joined(separator: "\n")
        case .plain:
            return texts.map { $0 + "\n" }.joined()
        }
    }

    /// word tokens with per-word provenance: maximal runs of scalars that are not
    /// space/tab (nor nbsp when that rule is on); token text runs through the same
    /// canonical pipeline as lines at l3 (sdd §6.3)
    static func wordTokens(_ content: [ScalarItem], profile: Profile, rules: RuleSet) -> [Token] {
        var runs: [[ScalarItem]] = []
        var run: [ScalarItem] = []
        for item in content {
            let v = item.scalar.value
            let isWS = isSpaceOrTab(v) || (item.scalar == nbsp && rules.nbspToSpace)
            if isWS {
                if !run.isEmpty {
                    runs.append(run)
                    run = []
                }
            } else {
                run.append(item)
            }
        }
        if !run.isEmpty {
            runs.append(run)
        }
        var tokens: [Token] = []
        tokens.reserveCapacity(runs.count)
        for r in runs {
            let text = canonLine(r, level: 3, profile: profile, rules: rules)
            if text.isEmpty {
                continue  // nothing but invisibles
            }
            guard let first = r.first, let last = r.last else { continue }
            tokens.append(Token(text: text, range: first.start..<last.end))
        }
        return tokens
    }

    /// units for l3 alignment with provenance: paragraphs (prose) or lines
    /// (code/plain); blank material between units is gap, not unit (sdd §6.3)
    static func buildUnits(_ s: String, profile: Profile, rules: RuleSet, sensitive: Bool) -> [Unit] {
        let lines = splitLines(scalarItems(s))
        var units: [Unit] = []
        switch effectiveL3(profile: profile, rules: rules, sensitive: sensitive) {
        case .prose:
            var currentTokens: [Token] = []
            for line in lines {
                let l2 = canonLine(line.content, level: 2, profile: profile, rules: rules)
                if l2.isEmpty {
                    if !currentTokens.isEmpty {
                        units.append(makeUnit(currentTokens))
                        currentTokens = []
                    }
                } else {
                    currentTokens.append(contentsOf: wordTokens(line.content, profile: profile, rules: rules))
                }
            }
            if !currentTokens.isEmpty {
                units.append(makeUnit(currentTokens))
            }
        case .code, .plain:
            let eff = effectiveL3(profile: profile, rules: rules, sensitive: sensitive)
            for line in lines {
                let l2 = canonLine(line.content, level: 2, profile: profile, rules: rules)
                var text: String
                if eff == .code {
                    if l2.isEmpty && rules.ignoreBlankLinesEntirely {
                        continue
                    }
                    text = rules.ignoreIndentation ? stripLeadingSpacesTabs(l2) : l2
                } else {
                    text = l2
                    if text.isEmpty {
                        continue  // blank lines are gaps between units, not units
                    }
                }
                guard let first = line.content.first, let last = line.content.last else {
                    continue  // no original bytes to anchor provenance
                }
                let tokens = wordTokens(line.content, profile: profile, rules: rules)
                if tokens.isEmpty {
                    continue  // nothing but invisibles: gap material
                }
                units.append(Unit(text: text, range: first.start..<last.end, tokens: tokens))
            }
        }
        return units
    }

    private static func makeUnit(_ tokens: [Token]) -> Unit {
        let text = tokens.map(\.text).joined(separator: " ")
        let start = tokens.first?.range.lowerBound ?? 0
        let end = tokens.last?.range.upperBound ?? 0
        return Unit(text: text, range: start..<end, tokens: tokens)
    }
}
