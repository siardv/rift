import Foundation

/// cheap, explainable content-profile detection (sdd §3.3, §6.2). scores each
/// side independently on linear features over a bounded sample; sides must
/// agree, ties and disagreement fall back to plain, which never reflows
enum ContentDetector {
    static let sampleLimit = 65536  // unicode scalars per side (o(1) for huge inputs)

    struct SideResult {
        let profile: Profile
        let confidence: Double
    }

    private static let codeChars: Set<Unicode.Scalar> =
        ["{", "}", "(", ")", ";", "=", "<", ">", "[", "]", "&", "|"]
    private static let keywordSet: Set<String> = [
        "func", "let", "var", "def", "class", "import", "return", "if", "else",
        "for", "while", "const", "fn", "pub", "public", "private", "void", "int",
        "float", "struct", "enum", "static", "new", "print", "end", "function",
    ]
    private static let sentenceEnd: Set<Unicode.Scalar> = [".", "!", "?", "\u{2026}"]
    private static let sentenceTrim: Set<Unicode.Scalar> = ["\"", "'", ")", "]", "\u{201D}", " "]
    private static let semiEnd: Set<Unicode.Scalar> = [";", "{", "}", ")", ","]
    private static let keywordTrim: Set<Unicode.Scalar> = ["(", ")", ":", ";", "{", "}", ","]

    private static func isUnicodeWhitespace(_ s: Unicode.Scalar) -> Bool {
        s.properties.isWhitespace
    }

    private static func sample(_ s: String) -> [Unicode.Scalar] {
        Array(s.unicodeScalars.prefix(sampleLimit))
    }

    private static func rawLineTexts(_ scalars: [Unicode.Scalar]) -> [[Unicode.Scalar]] {
        var lines: [[Unicode.Scalar]] = []
        var current: [Unicode.Scalar] = []
        var i = 0
        while i < scalars.count {
            let v = scalars[i].value
            if v == 0x0D {
                if i + 1 < scalars.count && scalars[i + 1].value == 0x0A {
                    i += 1
                }
                lines.append(current)
                current = []
            } else if v == 0x0A {
                lines.append(current)
                current = []
            } else {
                current.append(scalars[i])
            }
            i += 1
        }
        if !current.isEmpty {
            lines.append(current)
        }
        return lines
    }

    private static func trimmed(_ line: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var lo = 0
        var hi = line.count
        while lo < hi && isUnicodeWhitespace(line[lo]) { lo += 1 }
        while hi > lo && isUnicodeWhitespace(line[hi - 1]) { hi -= 1 }
        return Array(line[lo..<hi])
    }

    private static func endsSentence(_ line: [Unicode.Scalar]) -> Bool {
        var hi = line.count
        while hi > 0 && sentenceTrim.contains(line[hi - 1]) { hi -= 1 }
        guard hi > 0 else { return false }
        return sentenceEnd.contains(line[hi - 1])
    }

    private static func splitWords(_ line: [Unicode.Scalar]) -> [[Unicode.Scalar]] {
        var words: [[Unicode.Scalar]] = []
        var current: [Unicode.Scalar] = []
        for sc in line {
            if isUnicodeWhitespace(sc) {
                if !current.isEmpty {
                    words.append(current)
                    current = []
                }
            } else {
                current.append(sc)
            }
        }
        if !current.isEmpty {
            words.append(current)
        }
        return words
    }

    private static func keywordCore(_ word: [Unicode.Scalar]) -> String {
        var lo = 0
        var hi = word.count
        while lo < hi && keywordTrim.contains(word[lo]) { lo += 1 }
        while hi > lo && keywordTrim.contains(word[hi - 1]) { hi -= 1 }
        return String(String.UnicodeScalarView(word[lo..<hi]))
    }

    static func detectSide(_ s: String) -> SideResult {
        let scalars = sample(s)
        let lines = rawLineTexts(scalars)
        let nonblank = lines.filter { $0.contains { !isUnicodeWhitespace($0) } }
        if nonblank.isEmpty {
            return SideResult(profile: .plain, confidence: 0.0)
        }
        let stripped = nonblank.map(trimmed)
        // json probe: a valid json container gets the code profile in v1 (sdd §3.3)
        let trimmedSample = trimmed(scalars)
        if let first = trimmedSample.first, first == "{" || first == "[" {
            let text = String(String.UnicodeScalarView(trimmedSample))
            if (try? JSONSerialization.jsonObject(with: Data(text.utf8))) != nil {
                return SideResult(profile: .code, confidence: 0.9)
            }
        }
        let n = Double(stripped.count)
        let punctRatio = Double(stripped.filter(endsSentence).count) / n
        let semiRatio = Double(stripped.filter { line in
            if let last = line.last { return semiEnd.contains(last) }
            return false
        }.count) / n
        var totalChars = 0
        var codeCharCount = 0
        var words: [[Unicode.Scalar]] = []
        for line in stripped {
            totalChars += line.count
            codeCharCount += line.filter { codeChars.contains($0) }.count
            words.append(contentsOf: splitWords(line))
        }
        let codeDensity = Double(codeCharCount) / Double(max(totalChars, 1))
        let kwHits = words.filter { keywordSet.contains(keywordCore($0)) }.count
        let kwPerLine = Double(kwHits) / n
        let indentRatio = Double(nonblank.filter { line in
            if let first = line.first { return first == " " || first == "\t" }
            return false
        }.count) / n
        let avgWords = Double(words.count) / n
        let codeScore = 2.5 * min(codeDensity * 12.0, 1.0)
            + 1.2 * min(kwPerLine, 1.0)
            + 0.6 * indentRatio
            + 1.2 * semiRatio
        let proseScore = 2.5 * punctRatio + (avgWords >= 5 ? 1.0 : avgWords / 5.0)
        let margin = codeScore - proseScore
        if margin > 0.5 {
            return SideResult(profile: .code, confidence: min(margin / 3.0, 1.0))
        }
        if margin < -0.5 {
            return SideResult(profile: .prose, confidence: min(-margin / 3.0, 1.0))
        }
        return SideResult(profile: .plain, confidence: 0.2)
    }

    /// conservative indentation-sensitivity heuristic (sdd §3.3, r-8): when in
    /// doubt, indentation stays significant
    static func indentationSensitive(_ s: String) -> Bool {
        let lines = rawLineTexts(sample(s))
        let nonblank = lines.filter { $0.contains { !isUnicodeWhitespace($0) } }
        if nonblank.isEmpty {
            return false
        }
        let n = Double(nonblank.count)
        let colonEnds = Double(nonblank.filter { line in
            let t = trimmed(line)
            return t.last == ":"
        }.count) / n
        let indented = Double(nonblank.filter { line in
            if let first = line.first { return first == " " || first == "\t" }
            return false
        }.count) / n
        let yamlish = Double(nonblank.filter(isYamlKeyLine).count) / n
        return (colonEnds >= 0.05 && indented >= 0.2) || yamlish >= 0.3
    }

    private static func isYamlKeyLine(_ line: [Unicode.Scalar]) -> Bool {
        // mirrors ^\s*[A-Za-z0-9_-]+:(\s|$)
        var i = 0
        while i < line.count && isUnicodeWhitespace(line[i]) { i += 1 }
        var keyLength = 0
        while i < line.count {
            let v = line[i].value
            let isKeyChar = (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A)
                || (v >= 0x30 && v <= 0x39) || v == 0x5F || v == 0x2D
            if isKeyChar {
                keyLength += 1
                i += 1
            } else {
                break
            }
        }
        guard keyLength > 0, i < line.count, line[i] == ":" else { return false }
        let after = i + 1
        return after == line.count || isUnicodeWhitespace(line[after])
    }

    /// combines both sides (agreement required, ties fall to plain) and adds the
    /// indentation-sensitivity flag for code (sdd §6.2)
    static func detect(_ a: String, _ b: String, override: Profile?) -> DetectedProfile {
        let profile: Profile
        let confidence: Double
        let isAutomatic: Bool
        let explanation: String
        if let forced = override {
            profile = forced
            confidence = 1.0
            isAutomatic = false
            explanation = "override"
        } else {
            let ra = detectSide(a)
            let rb = detectSide(b)
            if ra.profile == rb.profile {
                profile = ra.profile
                confidence = min(ra.confidence, rb.confidence)
            } else {
                profile = .plain
                confidence = 0.2
            }
            isAutomatic = true
            explanation = "a=\(ra.profile.rawValue)(" + String(format: "%.2f", ra.confidence)
                + ") b=\(rb.profile.rawValue)(" + String(format: "%.2f", rb.confidence) + ")"
        }
        var sensitive = false
        if profile == .code {
            sensitive = indentationSensitive(a) || indentationSensitive(b)
        }
        return DetectedProfile(profile: profile, isAutomatic: isAutomatic,
                               confidence: confidence,
                               isIndentationSensitive: sensitive,
                               explanation: explanation)
    }
}
