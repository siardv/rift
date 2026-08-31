# Contributing to Rift

Thanks for helping. Two ground rules keep contributions easy to accept: the engine stays a pure, platform-independent Swift package with zero third-party dependencies and no UI imports (SDD §5.1), and behavioral claims are backed by tests.

## The golden corpus — start here

The most valuable contribution requires no Swift at all: a corpus case demonstrating a comparison Rift should get right, especially tricky boundaries between presentational and substantive change. Each case is a folder under `RiftEngine/Tests/RiftEngineTests/Corpus/`:

```
Corpus/<case_name>/
├── left.txt
├── right.txt
└── expected.json
```

The format, working `expected.json` schema, and authoring guidance are documented in [the corpus README](RiftEngine/Tests/RiftEngineTests/Corpus/README.md) and SDD §10. Keep cases minimal — one phenomenon per case, snake_case folder names. The harness that executes the corpus lands with M1; cases merged before then are ready and waiting.

## Code contributions

Read [docs/sdd.md](docs/sdd.md) first; it is the authoritative design. Generate the Xcode project with `xcodegen generate` (Rift.xcodeproj is deliberately untracked). Engine work must keep `cd RiftEngine && swift test` green on macOS and Linux — CI runs both. Determinism is a contract: identical inputs always produce identical reports, and every classification must be explainable by a named rule (SDD §1.5); no heuristic whose outcome cannot be explained in one line.

## Reporting bugs

The best bug report is a corpus pair: the two texts plus what you expected Rift to say.

## License

By contributing you agree your work is licensed under the project's [MIT license](LICENSE). No CLA — inbound = outbound.
