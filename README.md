# Rift

**See what actually changed.**

Rift compares two texts and answers, verdict-first, whether substantive content changed — automatically setting aside presentational differences (line endings, trailing spaces, space runs, blank-line runs, hard-wrap reflow, indentation) without any manual ignore-toggles. Everything set aside is counted and revealable, never silently discarded.

Free and open source, with offline comparison, no accounts, and no analytics. iPhone + iPad, iOS 17+. The planned App Store listing is *Rift — Text & Code Diff*; on your device it is simply **Rift**.

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

**0.1.0 candidate.** The native iPhone and iPad app includes focused source editing, automatic comparison, the strictness ladder with provenance, and summary and patch exports. The engine and app tests pass locally and in CI. Physical device acceptance and App Store submission remain pending; Rift is not yet available on the App Store.

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
