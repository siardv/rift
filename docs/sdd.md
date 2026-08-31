# Rift — Software Design Document

| Field | Value |
|---|---|
| Project | Rift — a content-aware diff app for iOS |
| Document | Software Design Document (SDD), v0.1, draft for implementation |
| Date | 2026-08-30 |
| Owner | Siard van den Bosch |
| License | MIT (decided 2026-08-30) |
| Platform | iPhone + iPad, iOS 17.0+, SwiftUI, Swift 6 (built with Xcode 26.x) |
| Distribution | App Store (free, no IAP, no ads) + public GitHub repository |
| Repository (proposed) | `github.com/siardv/rift` |

---

## 1. Introduction

### 1.1 Purpose of this document

This document specifies the design of Rift version 1.0 and the architectural decisions that let later versions grow without rework. It is written to be actionable by a single developer working in short sessions: every section either constrains the implementation or can be deferred, and each is marked accordingly. It doubles as the design reference that ships in the open-source repository (`docs/sdd.md`).

### 1.2 Product summary

Rift compares two pieces of text and answers the question existing diff tools make the user answer for themselves: **has the substantive content changed, and if so, where and how?** Instead of offering checkboxes for "ignore whitespace", "ignore blank lines", and "ignore line endings", Rift evaluates the two texts at several strictness levels automatically, reports the level at which they converge, and presents content changes separately from formatting noise. The user pastes or loads two texts and reads a verdict; configuration is possible but never required.

The name is the product metaphor: the *rift* is the genuine gap between two texts. Rift's job is to measure that gap honestly — and to say plainly when there is none.

### 1.3 Goals

| # | Goal |
|---|---|
| G-1 | A first comparison must require zero configuration and zero learning: paste, paste, read the verdict. |
| G-2 | Presentational differences (line endings, trailing spaces, space runs, blank-line runs, hard-wrap reflow, indentation) are recognized, counted, and set aside automatically — never silently discarded, never mixed in with content changes. |
| G-3 | Advanced control exists (strictness override, per-rule toggles, profile override) but lives behind progressive disclosure; defaults are good enough that most users never open it. |
| G-4 | The diff engine is a pure, platform-independent Swift package that can later power a macOS app, a share extension, Shortcuts actions, and a CLI without modification. |
| G-5 | Shippable v1.0 in roughly four focused days; every later feature slots into an existing extension point rather than forcing refactors. |
| G-6 | Fully open source (MIT), fully offline, no accounts, no analytics, no network access at all. |
| G-7 | Visual design that is clean and modern with a quiet academic register: serif display type, restrained color, typographic care. |

### 1.4 Non-goals (v1.0)

Merge (2-way or 3-way), folder comparison, git integration, image comparison, syntax highlighting, cloud sync, iCloud document browsing, collaboration, Android/web ports, and any AI/LLM-based judgment of "meaning". The engine is deterministic by principle: the same inputs always produce the same verdict, and every classification is explainable by a named rule. Several non-goals are deliberate roadmap items (§15); others (git, merge) are permanently out of scope because Kaleidoscope-class desktop tools own them.

### 1.5 Guiding principles

**Verdict first.** The primary output is a sentence, not a wall of colored lines. The colored lines are the evidence for the sentence.

**Never hide, always account.** Smart normalization must not silently swallow differences. Everything ignored at the content level remains counted, listed, and one tap away. This is the trust contract that makes automatic behavior acceptable.

**Progressive disclosure.** One obvious path on the surface; depth on demand. The advanced layer may resemble CodeDiff+'s toggle sheet — that is fine, because it is the *fallback*, not the front door.

**Engine before pixels.** All intelligence lives in the engine package where it is unit-testable. The UI renders a `DiffReport`; it never computes.

**Determinism and explainability.** Every difference Rift sets aside is attributable to a named normalization rule at a named level. No heuristics whose output cannot be explained in one line to the user.

---

## 2. Background and competitive context

### 2.1 CodeDiff+ (Nitrio "Code Compare", iOS) — as-is analysis

The incumbent on the phone. Per its product page and the current paid version (1.x, iOS 18.6+, ~1.7 MB): two panes with paste/load per side, per-pane search, swap, side-by-side (landscape) or stacked (portrait) layout, iPad SplitView, jump to next/previous change, font/spacing/word-wrap viewer settings, and four manual diff options — ignore whitespace, ignore line endings, ignore case, character-level inline mode. Export covers copy, save as text/JSON, and a side-by-side screenshot.

Its limitations define Rift's opportunity:

| # | Limitation | Consequence for the user |
|---|---|---|
| C-1 | All ignore-behavior is manual, global toggles | The user must predict which noise the texts contain *before* reading the result, then re-run mentally when wrong |
| C-2 | Strictly line-based comparison | A hard-wrap reflow (same words, different line breaks) shows as large spurious change blocks; no toggle fixes this, because the line structure itself differs |
| C-3 | No summary or verdict | The central question — "did content change?" — is answered by visually scanning the whole output |
| C-4 | No notion of content type | Prose, code, JSON, and logs all get the same treatment |
| C-5 | No accounting of what was ignored | With "ignore whitespace" on, whitespace differences vanish without a trace; the user cannot audit what was suppressed |
| C-6 | Viewer-grade output | No word-level prose presentation; monospaced grid regardless of content |

### 2.2 Kaleidoscope 6.7 (10249), macOS — what it solves better

Kaleidoscope is the reference for *visualization*: character-level in-line highlighting, collapsible unchanged regions (v6.0+), fluid/unified/two-pane layouts, image and folder scopes, three-way merge, deep git integration, `ksdiff` CLI, and editor/IDE integrations. Two of its features are directly relevant prior art for Rift:

- **Ignore-whitespace display option** — a manual, global toggle, same conceptual model as CodeDiff+, just better executed.
- **Text Filters** (since v4, 2023) — user-authored ICU regular expressions applied per document to rewrite noise (timestamps, UUIDs, object addresses) into identical placeholder symbols before comparison. Powerful, but each filter is hand-written, manually selected per comparison, and shared across contexts. It is a professional's scalpel, not an automatic instrument.

Note: Kaleidoscope today is macOS-only (an iPad version existed around 2015 under a previous owner and was discontinued), and version 7 (July 2026) moved to subscription pricing. On iOS the field is effectively open.

### 2.3 The gap neither tool fills

Neither tool — nor `git diff`'s `--ignore-*` flags, `wdiff`/`dwdiff`, or difftastic's syntax-tree diffing — does all four of the following at once:

1. **Decide automatically** which differences are presentational, using the content itself, instead of asking the user to pre-select ignore rules.
2. **See through reflow**: treat hard-wrapped prose as the paragraph it is, so re-wrapped text with identical words compares as identical. (Line-based tools cannot do this even with every whitespace option enabled, because the *line structure* differs; `git diff --word-diff --ignore-all-space` comes closest but is a manual CLI incantation with no verdict.)
3. **Lead with a verdict** and treat the highlighted text as supporting evidence.
4. **Account for what was set aside**, so automation never becomes silent data loss.

Closest prior art for the *classification* idea is Microsoft Word's document compare, which separates "formatting" changes from content changes — but for rich text, not plain text, and not on iOS. Difftastic proves content-aware diffing works (via tree-sitter parse trees) but targets code exclusively, runs as a CLI, and ignores prose entirely.

### 2.4 Positioning

Rift is not a Kaleidoscope competitor. It is the tool for the moment Kaleidoscope is too far away and CodeDiff+ answers the wrong question: a fast, honest, beautiful answer to "what actually changed?" on the device in your hand. Deep scopes (folders, images, merge, git) stay on the desktop.

---

## 3. Conceptual model

This section is the heart of the design; everything else is delivery mechanics.

### 3.1 Substantive vs. presentational

A difference is **presentational** when a defined, content-preserving normalization maps both texts to the same form — the difference is in how the text is *laid out*, not in what it *says*. Everything else is **substantive**: insertions, deletions, and replacements of actual content. Rift's engine formalizes "content-preserving" as a small set of named, ordered normalization rules; a difference is presentational exactly when some rule set eliminates it. This keeps the concept explainable: Rift never claims semantic understanding, only rule-based equivalence.

### 3.2 The strictness ladder

The engine evaluates equality at cumulative levels. Each level adds normalizations to the previous one; every rule is named and per-profile (§3.3):

| Level | Name | Normalizations added (generic) | Typical cause eliminated |
|---|---|---|---|
| L0 | Exact | none — texts as given | — |
| L1 | Encoding | Unicode NFC; CRLF/CR → LF; strip BOM and zero-width/invisible format characters; strip trailing whitespace per line; normalize trailing newline at EOF | Files from different platforms/editors |
| L2 | Spacing | collapse runs of spaces/tabs within a line to one space; collapse blank-line runs to one; trim leading/trailing blank lines; NBSP → space; (prose) typographic equivalence: curly↔straight quotes, en/em dash ↔ hyphen forms, ellipsis ↔ three dots | Reformatting, copy-paste artifacts, typographic auto-correction |
| L3 | Layout | (prose) reflow: single line breaks inside a paragraph become spaces — paragraphs, separated by blank lines, are the unit; (code) leading indentation ignored; blank lines between code lines ignored | Hard re-wrapping, re-indentation |
| — | Content | whatever still differs after L3 | Real edits |

The engine computes, cheaply, the lowest level at which the two texts become equal — the **convergence level** — and, when they never converge, the set of content changes plus the count of formatting-only differences resolved along the way. The ladder subsumes every CodeDiff+ toggle (ignore line endings ≈ L1, ignore whitespace ≈ L2, plus reflow at L3, which no toggle there can express) while requiring no decisions from the user, because *all* levels are always evaluated.

Two rules are deliberately **excluded** from the ladder and exist only as opt-in Custom-mode toggles, because they change meaning rather than layout: ignore case, and ignore punctuation. Typographic equivalence is ladder-included for prose but excluded for code, where quote characters are syntax.

Paragraph-boundary edits are the one genuinely ambiguous case: inserting a blank line that *splits* a paragraph changes structure, not just spacing. The ladder handles this naturally — a split changes the L3 canonical form (two paragraphs where one was), so it surfaces as a content-level change, labeled specifically as *paragraph split/merge* rather than as a text edit. Merely changing one blank line to three between existing paragraphs resolves at L2.

### 3.3 Content profiles and auto-detection

A **profile** parameterizes the ladder's rules. v1.0 ships three:

| Profile | L3 meaning | Typographic equivalence | Notes |
|---|---|---|---|
| Prose | reflow into paragraphs; compare word streams | on | default for natural language |
| Code | indentation and blank lines ignored at L3 *unless* the text looks indentation-sensitive (Python/YAML-like), in which case indentation stays significant and the verdict says so | off | line remains the display unit |
| Plain | L3 = L2 (no layout level) | off | fallback and explicit "Strict-ish" base |

Detection is a cheap, explainable heuristic scored per side (agreement required; ties → Plain): ratio of lines ending in sentence punctuation, average/percentile line lengths, density of `{};=()` and keyword-like tokens, indentation regularity, markdown markers, and a quick "does it parse as JSON" probe (JSON gets the Code profile in v1.0; a true structural JSON profile is roadmap §15). The detected profile is displayed as a tappable chip ("Prose · auto") so the user can always see and override the decision — automation stays inspectable.

### 3.4 Verdict model

The verdict is a total function of (convergence level, change counts):

| Situation | Banner (primary line) | Secondary line |
|---|---|---|
| Equal at L0 | Identical. | byte-for-byte |
| Equal at L1 | Same content. | differ only in line endings / trailing space — *n* places |
| Equal at L2 | Same content. | differ only in spacing / blank lines — *n* places |
| Equal at L3 | Same content. | differ only in layout (wrapping / indentation) — *n* places |
| Not equal | *k* content changes. | plus *m* formatting-only differences |

The formatting count *m* is computed by comparing raw slices (via the provenance map, §6.3) inside regions the content diff says are equal — so nothing ignored is ever unaccounted for. Tapping the secondary line reveals the formatting differences dimmed in place; tapping the banner jumps to the first content change.

### 3.5 Worked examples

**Reflow (the founding use case).** A: `The quick brown fox\njumps over the lazy dog.` B: `The quick brown fox jumps over the lazy dog.` — Line-based tools show one deleted and two inserted lines (or a changed pair). Rift: prose profile, converges at L3 → *"Same content. Differ only in layout — 1 place."*

**Mixed.** A has double blank lines between paragraphs and the word `colour`; B has single blank lines and `color`. Rift: 1 content change (`colour → color`, word-level highlight) plus *"3 formatting-only differences"* (the blank-line runs, resolved at L2). CodeDiff+ with all toggles on still shows every affected line pair as changed; with toggles off it shows everything as changed.

**Code hygiene.** B differs from A by CRLF endings, trailing spaces, and one renamed variable. Rift: 1 content change; the noise resolves at L1 and is counted, not shown. The verdict names the rename's line.

---

## 4. Requirements

### 4.1 Functional requirements

MVP = must ship in 1.0. Later = designed-for now, built later (§15).

| ID | Requirement | Phase |
|---|---|---|
| FR-1 | Accept text per side via paste button, direct typing/editing, Files import (`fileImporter`, plain-text UTTypes), and drag & drop (iPad/pointer) | MVP |
| FR-2 | Compare automatically (debounced ~300 ms) whenever both sides are non-empty; explicit Compare button not required | MVP |
| FR-3 | Run the full strictness ladder and display the verdict banner per §3.4 | MVP |
| FR-4 | Auto-detect content profile per §3.3; show as chip; allow override (Prose / Code / Plain) | MVP |
| FR-5 | Three modes: **Smart** (default, ladder-driven), **Strict** (L0; show everything), **Custom** (manual rule toggles, including ignore-case) — a segmented control in the inspector | MVP |
| FR-6 | Present content changes with intra-change refinement: word-level for prose, character/word-level within lines for code | MVP |
| FR-7 | Two result presentations: unified/inline (default in portrait) and side-by-side (default in landscape and on iPad); user-switchable | MVP |
| FR-8 | Prose reading view: paragraphs rendered as flowing serif text with inline insert/delete highlights (Track-Changes-like), not a monospaced line grid | MVP |
| FR-9 | Navigate previous/next change; change counter ("2 of 7"); tap verdict to jump to first change | MVP |
| FR-10 | Reveal formatting-only differences on demand (dimmed in place + list in inspector), per §3.4 | MVP |
| FR-11 | Swap sides; clear side; character/line/word count per side | MVP |
| FR-12 | Share/export: plain-text summary (verdict + changes) and unified `.patch` file via share sheet; copy any change's before/after | MVP |
| FR-13 | Sample pair on the empty state ("Try an example") so the first-run experience and App Review need no source material | MVP |
| FR-14 | Viewer settings: font size, monospaced toggle for code view, light/dark/system, accessible palette toggle | MVP |
| FR-15 | Persist last inputs and settings across launches (local only); "recent comparisons" history | Later (1.x) |
| FR-16 | Share-sheet extension ("Send to Rift" fills A, then B) | Later (1.1) |
| FR-17 | Structural profiles: Markdown-aware, JSON canonicalization (key order, number forms), CSV | Later (1.x) |
| FR-18 | Shortcuts / App Intents: CompareTexts intent returning verdict + counts | Later (1.2) |
| FR-19 | Moved-block detection (`inferringMoves`-style) rendered as moves, not delete+insert | Later |
| FR-20 | Syntax highlighting in code view | Later |
| FR-21 | macOS app reusing RiftEngine unchanged | Later (2.0) |

### 4.2 Non-functional requirements

| ID | Requirement |
|---|---|
| NFR-1 | **Performance:** full ladder + refined diff for 1 MB / ~25 k lines in < 300 ms on an A15 (iPhone 13); UI never blocks — diff runs off the main actor with cancellation on new input |
| NFR-2 | **Capacity:** inputs up to 4 MB per side; beyond a soft threshold (~1 MB) refinement degrades gracefully (line/paragraph granularity only) with a visible note; hard cap with a clear message |
| NFR-3 | **Determinism:** identical inputs + settings ⇒ identical `DiffReport`, on every device, every run |
| NFR-4 | **Privacy:** no network entitlement used; no analytics/telemetry of any kind; App Privacy label "Data Not Collected" |
| NFR-5 | **Accessibility:** all colors meet WCAG AA against their backgrounds; insertions/deletions additionally marked by glyphs (+/−) and underline/strikethrough so color is never the sole channel; full Dynamic Type; VoiceOver reads changes as "changed: ⟨old⟩ to ⟨new⟩"; optional blue/orange palette |
| NFR-6 | **Quality:** engine ≥ 90 % line coverage; golden corpus + property tests green in CI (macOS and Linux) before any release |
| NFR-7 | **Footprint:** app under ~5 MB download; zero third-party runtime dependencies in v1.0 |
| NFR-8 | **Internationalization-ready:** all user-facing strings in a String Catalog; English ships first; grapheme-cluster-correct diffing for emoji/combining marks; bidi-safe rendering |

---

## 5. Architecture

### 5.1 Overview

Two layers, one dependency arrow. `RiftEngine` is a local Swift package with no UI imports and no third-party dependencies; the app target renders what the engine reports. Future clients (share extension, App Intents, macOS app, CLI) consume the same package unchanged — this is the expansion mechanism that keeps v1.0 small without painting the project into a corner.

```
rift/
├── Rift.xcodeproj
├── Rift/                          # app target (SwiftUI, iOS 17+)
│   ├── RiftApp.swift
│   ├── State/
│   │   ├── CompareSession.swift   # @Observable; owns inputs, options, DiffReport, running Task
│   │   └── SettingsStore.swift    # @AppStorage-backed
│   ├── Screens/
│   │   ├── CompareScreen.swift    # single main screen: panes + verdict + result
│   │   ├── InspectorSheet.swift   # mode, profile, ladder readout, rule toggles
│   │   ├── SettingsScreen.swift
│   │   └── AboutScreen.swift      # license, source link, acknowledgements
│   ├── Components/
│   │   ├── PaneCard.swift  VerdictBanner.swift  LadderView.swift
│   │   ├── ProseDiffView.swift  CodeDiffView.swift  DiffRow.swift
│   │   └── ChangeNavigator.swift
│   └── Support/                   # Theme.swift, Export.swift, Haptics.swift, SampleContent.swift
├── RiftEngine/                    # local SPM package, platform-independent
│   ├── Package.swift
│   ├── Sources/RiftEngine/
│   │   ├── Model/                 # DiffReport, Verdict, Hunk, Segment, LadderResult, ChangeKind
│   │   ├── Detect/                # ContentDetector
│   │   ├── Normalize/             # rules, levels, profiles, provenance mapping
│   │   ├── Diff/                  # Aligner (Myers), Refiner (intra-unit), Pairing
│   │   ├── Classify/              # formatting accounting, paragraph split/merge labeling
│   │   └── RiftEngine.swift       # public facade
│   └── Tests/RiftEngineTests/     # unit + property tests, Corpus/ golden files
├── docs/                          # this SDD, screenshots, privacy policy page
├── .github/workflows/ci.yml
├── LICENSE  README.md  CONTRIBUTING.md
```

### 5.2 Engine public interface (sketch)

```swift
public struct CompareOptions: Sendable, Hashable {
    public var mode: Mode = .smart            // .smart, .strict, .custom(RuleSet)
    public var profileOverride: Profile? = nil // nil = auto-detect
}

public struct DiffReport: Sendable {
    public let verdict: Verdict               // .identical, .formattingOnly(level:count:), .changed(k:m:)
    public let profile: DetectedProfile       // which profile, why (score summary), auto vs override
    public let ladder: [LadderLevelResult]    // per level: equal?, formatting sites resolved
    public let document: DiffDocument         // ordered hunks for rendering
}

public struct DiffDocument: Sendable {
    public let hunks: [Hunk]                  // .equal, .change(ChangeKind), .formattingOnly
}
public struct Hunk: Sendable {
    public let kind: HunkKind
    public let unitsA: [Unit]                 // paragraphs (prose) or lines (code)
    public let unitsB: [Unit]
    public let segments: [Segment]            // refined word/char runs: .equal/.insert/.delete
    public let rangeA: Range<Int>             // UTF-8 offsets into ORIGINAL A (provenance)
    public let rangeB: Range<Int>
}

public enum RiftEngine {
    public static func compare(_ a: String, _ b: String,
                               options: CompareOptions = .init()) -> DiffReport
}
```

The facade is a pure synchronous function of value types; the *app* wraps it in a cancellable `Task` (§5.4). Purity is what makes the engine trivially testable, Linux-CI-able, and reusable from an App Intent.

### 5.3 App layer

State lives in one `@Observable` `CompareSession` (inputs, options, latest report, in-flight task). Views are function-of-state; no view computes diffs or classifications. Navigation is deliberately flat: one main screen, two sheets (Inspector, Settings). This is the entire UI surface of v1.0, which is what makes a four-day build honest.

### 5.4 Concurrency model

Swift 6 strict concurrency throughout. On input/option change: cancel the previous task, sleep ~300 ms (debounce), run `RiftEngine.compare` in a detached task at `.userInitiated`, check `Task.isCancelled` between pipeline stages (the engine takes a lightweight `isCancelled` closure), publish the report back on the main actor. Large-input degradation (NFR-2) is decided inside the engine so every client gets it for free.

### 5.5 Extension points (how later features slot in)

| Future feature | Slot |
|---|---|
| New profile (Markdown, JSON, CSV, per-language) | new `Profile` conformance in `Normalize/` + detector entry; UI chip picks it up automatically |
| Share extension / App Intents / CLI / macOS | new target depending on `RiftEngine`; no engine change |
| Better alignment (histogram/patience, moves) | swap implementation inside `Diff/Aligner` behind the same interface |
| Export formats (HTML report, styled PDF) | new renderer over `DiffDocument` in `Support/Export.swift` |
| History / persistence | new store observing `CompareSession`; engine untouched |

---

## 6. Engine design details

### 6.1 Ingestion

Inputs arrive as `String` (paste/typing) or `Data` + filename (Files). For data: reject likely-binary content (NUL byte or >10 % C0 controls in the first 8 KB) with a clear message; decode UTF-8, falling back to UTF-16 (BOM) then Latin-1 lossy with a visible "decoded as…" badge. Filename extension feeds the detector as a hint, never as an override.

### 6.2 Detection

`ContentDetector` scores each side independently on cheap linear features (§3.3) and returns `(Profile, confidence, features)` — the features power the inspector's one-line explanation ("Looks like prose: 78 % of lines end in punctuation, long soft lines"). Sides must agree; disagreement or low confidence falls back to Plain, which is always safe (it never reflows). Detection runs on ≤ 64 KB samples per side, so it is O(1) for huge inputs.

### 6.3 Normalization and provenance

Each level's canonicalization produces `CanonicalText`: an array of units (paragraphs or lines), each an array of tokens, where **every token carries its source range (UTF-8 offsets) in the original string**. Normalization therefore never loses the ability to point back at the exact original characters — this provenance map is what makes "never hide, always account" implementable: equality checks run on canonical forms, but rendering and formatting-accounting always address the originals. Canonicalization is per-side, single-pass, O(n), and idempotent (property-tested).

### 6.4 Ladder evaluation and alignment

Equality per level is a hash comparison of canonical forms — O(n) per level, so running all levels is cheap. Only when L3 forms differ does alignment run: Myers diff (via Swift's `CollectionDifference`, which implements Myers O((N+M)·D)) over *hashed units* — paragraphs for prose, lines for code — after trimming the common prefix/suffix. For repetitive inputs where Myers alignment is known to scatter (many identical units), a v1.x upgrade path to histogram/patience alignment is reserved inside `Aligner`; v1.0 accepts Myers plus prefix/suffix trimming as good enough.

Pathology guard: if unit-level similarity is below a threshold (e.g., < 15 % common units on large inputs), skip refinement and present a block-level "mostly rewritten" result instantly rather than burning O(N·D) time — with a note and a button to force full refinement.

### 6.5 Refinement and pairing

Changed unit runs are paired before refinement: a deleted and an inserted unit are treated as a *modification* (and refined) when their token-bigram Dice similarity ≥ 0.3, else as pure delete + insert. Refinement diffs the paired units' token streams — words for prose, words-then-characters for code lines — again via Myers, and emits `Segment` runs. Character-level work operates on `Character` (grapheme clusters), never Unicode scalars, so emoji and combining marks cannot be split. Intra-unit refinement is capped (~10 k characters per unit) to bound worst-case cost on minified one-line files.

### 6.6 Classification and formatting accounting

After alignment, regions that are content-equal are scanned via provenance: wherever the raw slices of A and B differ inside a content-equal region, a `formattingOnly` site is recorded with the responsible rule and level (e.g., "blank-line run, L2"). Paragraph split/merge detection (§3.2) runs here too: a content hunk whose token stream is unchanged but whose paragraph partitioning differs is relabeled `paragraphBoundary`. The sum of sites is the verdict's *m*; the list feeds the inspector.

### 6.7 Cost summary

Detection O(1); normalization O(n) per level; ladder O(n); alignment O((N+M)·D) on units (not characters), post-trim; refinement bounded per changed pair. Memory is O(n) with provenance stored as integer offsets (no substring copies). The NFR-1 budget is comfortable: 25 k hashed lines through Myers with a typical edit distance is milliseconds on A-series silicon; the dominant cost is string canonicalization, which is a single linear scan per level and can share work between levels (L2 canonicalizes L1's output).

---

## 7. UI/UX specification

### 7.1 Design language — "academic-clean"

The register the app should evoke: a well-set journal article, not a terminal. Concretely:

| Token | Choice |
|---|---|
| Display type | New York (system serif) for the wordmark, verdict banner, and section labels — `.fontDesign(.serif)` |
| Body/UI type | SF Pro; SF Mono only inside the code diff view |
| Ground | paper-toned neutrals (subtle warm off-white light / near-black dark), hairline separators, generous margins; no cards-on-cards, no gradients |
| Insertion | accessible green (tint + underline + "+" gutter glyph) |
| Deletion | accessible red (tint + strikethrough + "−" gutter glyph) |
| Formatting-only | dimmed ink at ~40 % with a dotted underline — visibly *other* than content changes |
| Alternate palette | blue/orange variant (settings toggle) for red-green color vision deficiency |
| Motion | none beyond system transitions; a single subtle haptic when a comparison completes with content changes |

The verdict banner is the identity moment of the app: one serif sentence, set large, e.g. **"Same content."** with the quiet secondary line beneath. It should feel like a finding, not a status bar.

### 7.2 Screen inventory and flow

One main screen; sheets for depth. Compare screen, top to bottom: (1) two compact input panes ("A", "B") as collapsed cards showing the first lines + counts once filled, each with Paste / Files / Clear and an editor on tap; (2) the verdict banner; (3) the result view. A trailing toolbar holds Swap, view-mode toggle (unified ⇄ side-by-side), the profile chip, and the Inspector button. Landscape and iPad ("regular width") place A and B panes side by side and default the result to two-pane.

The **Inspector sheet** is the progressive-disclosure home: mode control (Smart / Strict / Custom), the profile chip with the detector's one-line explanation, the **ladder readout** — a four-row visualization showing at which level the texts converge and how many differences each level resolved (this is the app's "show your work" view) — and, in Custom mode only, the individual rule toggles (the CodeDiff+ feature set, plus ignore-case, ignore-punctuation).

### 7.3 States

Empty (both panes blank): a one-line promise ("Paste two texts. Rift tells you what actually changed.") plus **Try an example**. One side filled: quiet hint on the other pane. Comparing (>150 ms): thin indeterminate bar under the banner area; previous result stays visible, dimmed. Oversized/binary/encoding issues: inline notices per §6.1/NFR-2. Identical: the full-width "Identical." banner *is* the result — no empty diff view pretending to have content.

### 7.4 Result presentation

**Prose:** unified reading view by default — paragraphs in serif, insertions and deletions inline (Track-Changes idiom), unchanged paragraphs collapsible to "⋯ 4 unchanged paragraphs" after the first screenful. **Code:** line grid in SF Mono with dual line-number gutters, +/− glyphs, word/char-level highlights within changed lines, unchanged runs collapsible with context (3 lines) — collapsing is what makes large files readable on a phone, and it is prior art validated by Kaleidoscope 6. Side-by-side mode uses synchronized scrolling; on iPhone portrait it remains available but not default. Change navigation (chevrons + "n of k") floats bottom-trailing; formatting-only sites appear only when revealed (FR-10), rendered in the dimmed style.

### 7.5 Interaction details

Tap a change: action row (copy A form, copy B form, copy both). Long-press the verdict: copies the verdict sentence — deliberately quotable. Every destructive action (Clear) is undoable via standard shake/three-finger undo rather than confirmation dialogs. All toggles apply live; the report recomputes with the debounce, so the inspector doubles as an exploratorium of the ladder.

### 7.6 Accessibility

Per NFR-5. Specific commitments: VoiceOver order is verdict → changes → panes; each change is one accessibility element ("Change 2 of 7, replaced: colour, with: color"); Dynamic Type reflows both views (the code view switches to wrapped lines with hanging indents at accessibility sizes); all touch targets ≥ 44 pt; reduce-motion honored trivially (there is no motion).

---

## 8. Data, persistence, privacy

v1.0 persists only viewer settings and options (`@AppStorage` / `UserDefaults`); inputs are held in memory and restored via standard scene state restoration where the system provides it. No files are written except user-initiated exports through the share sheet. There is no networking code path at all — the strongest privacy statement is structural absence, and it also makes App Review trivial. When history arrives (FR-15) it will be opt-in, local, and stored as plain files in the app container.

App Privacy questionnaire: **Data Not Collected** across the board. A one-page privacy policy (App Store requires a URL even for no-data apps) lives at `docs/privacy.md`, published via GitHub Pages.

## 9. Error handling and edge cases

| Case | Behavior |
|---|---|
| Both sides empty / one empty | Empty-state UX (§7.3); one side empty + one filled is *not* an error and produces no verdict |
| Identical inputs | "Identical." banner; no diff view |
| Binary sniff positive | Refuse with "This looks like a binary file" + filename; never render garbage |
| Encoding fallback used | Proceed + persistent "decoded as Latin-1" badge on the pane |
| Input > soft threshold (~1 MB) | Full ladder verdict; refinement degraded to unit level; note shown |
| Input > hard cap (4 MB) | Refuse politely with the limit stated |
| Extremely long single line (minified) | Refinement capped per §6.5; ladder still exact |
| Similarity below pathology threshold | "Mostly rewritten" block presentation + opt-in full refinement (§6.4) |
| Emoji / combining marks / flags | Grapheme-cluster diffing (§6.5); a skin-tone change is one change, not four scalar edits |
| RTL / bidi text | Views use natural layout direction; inline highlights wrap segments in bidi isolates to prevent visual reordering artifacts |
| Trailing newline at EOF differs | L1 formatting-only site, named exactly that |
| Mixed tabs/spaces indentation | L3 (code) formatting-only sites unless indentation-sensitive detection engaged, then substantive and the verdict says why |
| Engine task cancelled mid-run | No partial reports ever published; latest completed report remains on screen |

## 10. Testing strategy

**Golden corpus** (the backbone): `Tests/RiftEngineTests/Corpus/<case>/left.txt`, `right.txt`, `expected.json` (verdict, convergence level, change count, formatting count, hunk kinds). Cases mirror §3.5 and §9 — reflow, blank-line runs, CRLF/BOM, NBSP, smart quotes, paragraph split, indentation-only, rename-only, mixed, JSON-ish, minified, emoji, bidi, empty, identical, mostly-rewritten. Adding a regression test = adding a folder; contributors can do it without touching Swift.

**Property tests:** for arbitrary strings x, y: `compare(x, x)` is `.identical`; normalization is idempotent per level; ladder is monotone (differences resolved never decrease as level rises); every provenance range is valid, ordered, and non-overlapping; concatenating hunk ranges reconstructs both originals exactly.

**Performance tests:** XCTest `measure` on 1 MB prose and 25 k-line code fixtures against the NFR-1 budget, run in CI on macOS (numbers tracked, thresholds loose enough not to flake).

**UI:** v1.0 relies on the engine tests plus a handful of XCUITests for the critical path (paste → verdict → navigate → export). Snapshot tests are roadmap.

**CI (GitHub Actions):** job 1 `macos` — build app + `xcodebuild test` both schemes; job 2 `ubuntu` — `swift test` on RiftEngine only, which keeps the engine honestly platform-independent and lets non-Mac contributors run the full engine suite.

## 11. Repository and open-source setup

MIT `LICENSE` (decided; permissive and App-Store-safe — copyleft licenses have a documented history of conflict with App Store terms, e.g. the FSF/GNU Go takedown and VLC's relicensing). `README.md` leads with the verdict-first idea, one screenshot, the ladder table, and build instructions (`open Rift.xcodeproj`, no dependency manager steps — there are no dependencies). `CONTRIBUTING.md` points contributors at the golden corpus as the lowest-friction contribution. Conventional layout per §5.1; semantic-ish versioning (`1.0 (1)` marketing/build); tags per release; App Store metadata text kept in `docs/store/` so listing copy is versioned too. GitHub Issues with two templates (bug: attach a corpus pair; feature). No CLA — MIT inbound = outbound.

## 12. App Store submission plan

| Item | Plan |
|---|---|
| Bundle ID | reverse-DNS you control, e.g. `io.github.siardv.rift` (pattern in common use for GitHub-hosted apps) — decide once, it is permanent |
| App name on the store | **"Rift"** alone is already taken by an existing app, so the listing name needs a qualifier — e.g. `Rift — Text & Code Diff` (30-char limit) with subtitle `See what actually changed`; the icon label on device stays **Rift** (`CFBundleDisplayName`) |
| Category | Primary: Developer Tools; Secondary: Productivity |
| Price | Free, no IAP, no ads |
| Age rating | 4+ |
| Privacy | "Data Not Collected"; privacy policy URL from §8 |
| Export compliance | `ITSAppUsesNonExemptEncryption = NO` in Info.plist (no encryption beyond OS) — skips the per-build compliance question |
| Screenshots | Required sets at submission time (currently 6.9″ iPhone; 13″ iPad because iPad is supported); shots: verdict banner hero, prose reading view, code view, inspector/ladder, dark mode |
| Review notes | Point the reviewer at **Try an example** so the app demonstrates itself in one tap; state that the app is fully offline |
| Rejection risk | Main realistic risk is 4.2 minimal functionality for utility apps — mitigated by the sample content, polish level, and the genuinely novel ladder/verdict; no other guideline is in play (no accounts, no payments, no UGC, no network) |
| Rollout | TestFlight internal build first (same binary), then submit; expect first review in 1–2 days |

Toolchain note: build with Xcode 26.x (Swift 6.3 as of August 2026; Xcode 27 is in beta) with deployment target iOS 17.0. Nothing in this design requires APIs newer than iOS 17.

## 13. Milestones — the four-day plan

Each milestone ends in a runnable, committable state; stop-anywhere is a feature of the plan.

| Milestone | Budget | Contents | Done when |
|---|---|---|---|
| M0 — Skeleton | 0.5 day | repo, license, README stub, Xcode project + RiftEngine package, CI green, empty app runs on device | `swift test` passes on a trivial test in CI |
| M1 — Engine | 1 day | models, normalization L1–L3 + provenance, detector, ladder, Myers alignment + refinement + pairing, classification, verdict; golden corpus (~20 cases) + property tests | corpus green on macOS + Linux |
| M2 — UI | 1 day | CompareScreen, panes with paste/files, verdict banner, prose + code views, unified/side-by-side, navigation, inspector with ladder readout, settings, dark mode | end-to-end flow on device matches §7 |
| M3 — Polish | 0.5 day | accessibility pass (VoiceOver, Dynamic Type, palettes), haptic, empty/sample states, app icon, performance check against NFR-1, export | NFR-5 spot checks pass; export files open correctly |
| M4 — Ship | 0.5 day | screenshots, listing copy, privacy policy page, TestFlight, submit | build in review |

Total: ~3.5 focused days, with M1 the only technically dense day. If time pressure hits, FR-12 export and the side-by-side code mode are the designated cuts — never the ladder, the verdict, or the prose view, which are the product.

## 14. Risks

| # | Risk | Mitigation |
|---|---|---|
| R-1 | Scope creep (the classic side-project failure mode) | §1.4 non-goals; §15 gates; every "wouldn't it be nice" becomes a roadmap line, not a branch |
| R-2 | Auto-detection guesses wrong and undermines trust | Plain fallback is always safe; chip makes the decision visible and overridable in one tap; detector explains itself |
| R-3 | Smart mode perceived as hiding differences | The accounting contract (§3.4, FR-10): counts always shown, one tap to reveal; Strict mode always available |
| R-4 | Myers alignment quality on repetitive inputs | Prefix/suffix trim now; histogram/patience slot reserved (§5.5); pathology guard (§6.4) |
| R-5 | Store name conflict ("Rift" taken) | Qualified listing name decided up front (§12), device name unaffected |
| R-6 | App Review 4.2 | Sample content + polish + novel functionality (§12) |
| R-7 | Performance on pathological inputs | Caps, degradation ladder, cancellation (NFR-2, §6.4, §6.5) |
| R-8 | Indentation-sensitive code misclassified (Python reflowed as ignorable) | Indentation-sensitivity heuristic errs conservative: when in doubt, indentation stays significant (§3.3) |

## 15. Roadmap after 1.0

Ordered by leverage per effort, all pre-slotted in §5.5: **1.1** — share extension, `.patch`/HTML export polish, collapsible-region refinements, Markdown profile. **1.2** — App Intents/Shortcuts (verdict as a scriptable primitive is quietly powerful: "compare clipboard against file X on save"), moved-block detection, minimap strip. **1.3** — JSON/CSV structural profiles (canonical key order, number formats — the first step beyond layout into structure), per-language indentation knowledge. **2.0** — macOS (SwiftUI multiplatform; the engine is already portable), history, localization (Dutch first). Explicitly still out: merge, folders, git — the desktop tools own those, and Rift's identity is the verdict, not the workbench.

## 16. Appendices

### A. Normalization rules × profiles (v1.0 reference)

| Rule | Level | Prose | Code | Plain |
|---|---|---|---|---|
| Unicode NFC | L1 | ✓ | ✓ | ✓ |
| Line endings → LF | L1 | ✓ | ✓ | ✓ |
| Strip BOM / zero-width format chars | L1 | ✓ | ✓ | ✓ |
| Trailing whitespace per line | L1 | ✓ | ✓ | ✓ |
| EOF newline normalization | L1 | ✓ | ✓ | ✓ |
| Space/tab runs → one space (intra-line) | L2 | ✓ | ✓ | ✓ |
| Blank-line runs → one | L2 | ✓ | ✓ | ✓ |
| Leading/trailing blank lines trimmed | L2 | ✓ | ✓ | ✓ |
| NBSP → space | L2 | ✓ | ✓ | ✓ |
| Typographic equivalence (quotes/dashes/ellipsis) | L2 | ✓ | — | — |
| Reflow (intra-paragraph line breaks → spaces) | L3 | ✓ | — | — |
| Leading indentation ignored | L3 | — | ✓* | — |
| Blank lines ignored entirely | L3 | — | ✓* | — |
| Ignore case | opt-in only | Custom | Custom | Custom |
| Ignore punctuation | opt-in only | Custom | Custom | Custom |

\* suppressed when indentation-sensitivity is detected (§3.3); the verdict states this.

### B. Glossary

**Convergence level** — lowest ladder level at which both texts canonicalize to the same form. **Formatting-only site** — a location where raw slices differ inside a content-equal region, attributed to a rule + level. **Profile** — the rule parameterization chosen by detection or override. **Provenance** — per-token UTF-8 offset ranges into the originals, preserved through every normalization. **Unit** — the alignment granule: paragraph (prose) or line (code). **Verdict** — the banner sentence derived from convergence level and counts.

### C. References

- CodeDiff+ product page (Nitrio): https://www.nitrio.com/apps/CodeDiff_iOS_App.html
- Kaleidoscope: https://kaleidoscope.app/ · release notes (6.x/7.0): https://cloud.kaleidoscope.app/support/release-notes · Text Filters introduction: https://blog.kaleidoscope.app/2023/05/31/text-filters-in-kaleidoscope-4/
- Myers, E. W. (1986). *An O(ND) Difference Algorithm and Its Variations.* Algorithmica 1, 251–266.
- Swift `CollectionDifference` (Myers-based): https://developer.apple.com/documentation/swift/collectiondifference
- Difftastic (structural, tree-sitter-based diff; prior art for content-aware diffing): https://difftastic.wilfred.me.uk/
- GNU wdiff / dwdiff and `git diff --word-diff` — word-stream prior art for reflow-tolerant comparison
- GPL vs. App Store history (license decision context): https://www.theregister.com/2010/05/27/gnu_go_fsf_apple_itunes/ · https://developer.apple.com/forums/thread/722101
- Apple Human Interface Guidelines — layout, typography, accessibility: https://developer.apple.com/design/human-interface-guidelines

*End of document — Rift SDD v0.1. The next artifact to produce from this document is M0: the repository skeleton.*
