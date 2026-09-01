/// a canonical token with provenance: its normalized text plus the utf-8 byte
/// range it came from in the original string (sdd §6.3)
public struct Token: Sendable, Hashable {
    public let text: String
    public let range: Range<Int>

    public init(text: String, range: Range<Int>) {
        self.text = text
        self.range = range
    }
}

/// the alignment granule: a paragraph (prose) or line (code/plain), with its
/// canonical text, original byte range, and word tokens (sdd §6.3, glossary)
public struct Unit: Sendable, Hashable {
    public let text: String
    public let range: Range<Int>
    public let tokens: [Token]

    public init(text: String, range: Range<Int>, tokens: [Token]) {
        self.text = text
        self.range = range
        self.tokens = tokens
    }
}

/// what a hunk represents (sdd §5.2, §6.6)
public enum HunkKind: String, Sendable, Hashable, Codable {
    case equal
    case insertion
    case deletion
    case modification
    /// same words, different paragraph partitioning: a split or merge (sdd §3.2)
    case paragraphBoundary
}

/// how a segment inside a modification hunk relates the two sides
public enum SegmentOp: String, Sendable, Hashable, Codable {
    case equal
    case insert
    case delete
}

/// a refined run inside a modification hunk: word-level (or character-level for
/// closely paired code words). ranges point at the enclosing original spans;
/// character-level segments carry their enclosing token ranges (sdd §6.5)
public struct Segment: Sendable, Hashable {
    public let op: SegmentOp
    /// canonical text of the run on the side(s) it exists on
    public let text: String
    public let rangeA: Range<Int>?
    public let rangeB: Range<Int>?

    public init(op: SegmentOp, text: String, rangeA: Range<Int>?, rangeB: Range<Int>?) {
        self.op = op
        self.text = text
        self.rangeA = rangeA
        self.rangeB = rangeB
    }
}

/// one contiguous region of the comparison (sdd §5.2). `rangeA`/`rangeB` are
/// utf-8 byte ranges into the ORIGINAL strings; across the whole document the
/// hunk ranges tile each original exactly, so concatenating them reconstructs
/// both inputs byte for byte (sdd §10 property)
public struct Hunk: Sendable, Hashable {
    public let kind: HunkKind
    public let unitsA: [Unit]
    public let unitsB: [Unit]
    public let segments: [Segment]
    public let rangeA: Range<Int>
    public let rangeB: Range<Int>

    public init(kind: HunkKind, unitsA: [Unit], unitsB: [Unit],
                segments: [Segment], rangeA: Range<Int>, rangeB: Range<Int>) {
        self.kind = kind
        self.unitsA = unitsA
        self.unitsB = unitsB
        self.segments = segments
        self.rangeA = rangeA
        self.rangeB = rangeB
    }
}

/// why a report carries less refinement than usual (nfr-2, sdd §6.4)
public enum DegradationReason: String, Sendable, Hashable, Codable {
    /// input over the soft threshold: unit-level result, no intra-unit segments
    case softThreshold
    /// input over the hard cap: ladder verdict plus a coarse block result
    case inputTooLarge
    /// unit similarity below the pathology threshold: coarse block, no pairing
    case pathologicalInput
}

/// ordered hunks for rendering; the app renders this and never computes (sdd §5.2)
public struct DiffDocument: Sendable, Hashable {
    public let hunks: [Hunk]
    public let isDegraded: Bool
    public let degradationReason: DegradationReason?

    public init(hunks: [Hunk], isDegraded: Bool, degradationReason: DegradationReason?) {
        self.hunks = hunks
        self.isDegraded = isDegraded
        self.degradationReason = degradationReason
    }
}
