# Rift

**See what actually changed.**

Rift compares two texts and answers, verdict-first, whether substantive content changed — automatically setting aside presentational differences (line endings, trailing spaces, space runs, blank-line runs, hard-wrap reflow, indentation) without any manual ignore-toggles. Everything set aside is counted and revealable, never silently discarded.

Free, open source, fully offline: no accounts, no analytics, no network access at all. iPhone + iPad, iOS 17+. It ships on the App Store as *Rift — Text & Code Diff*; on your device it is simply **Rift**.

## The strictness ladder

Instead of asking you to pre-select ignore-checkboxes, Rift evaluates both texts at cumulative strictness levels and reports the level at which they converge:

| Level | Name | Normalizations added | Typical cause eliminated |
|---|---|---|---|
| L0 | Exact | none — texts as given | — |
| L1 | Encoding | Unicode NFC; CRLF/CR → LF; strip BOM and zero-width characters; trailing whitespace; EOF newline | files from different platforms/editors |
| L2 | Spacing | collapse space/tab runs and blank-line runs; NBSP → space; (prose) typographic equivalence | reformatting, copy-paste artifacts |
| L3 | Layout | (prose) hard-wrap reflow into paragraphs; (code) indentation and blank lines | re-wrapping, re-indentation |
| — | Content | whatever still differs after L3 | real edits |

Every token carries provenance back to the original bytes, so each ignored difference stays attributable to a named rule at a named level — one tap away, never hidden. The full design lives in [docs/sdd.md](docs/sdd.md).

## Status

**M0 — repository skeleton.** The engine's public API exists as a stub (`RiftEngine.compare(_:_:options:)`); the ladder, detector, and diff pipeline land with M1. Not yet on the App Store.

## Building

Requirements: Xcode 26.x and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The Xcode project is generated, not committed:

```
xcodegen generate
open Rift.xcodeproj
```

The engine is an independent Swift package with zero dependencies; it builds and tests anywhere Swift 6 runs, macOS or Linux, with no Xcode required:

```
cd RiftEngine
swift test
```

## Contributing

The lowest-friction contribution needs no Swift at all: a golden-corpus case — two texts plus the expected verdict. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE) © 2026 Siard van den Bosch
