# Golden corpus

This folder is the engine's executable specification (SDD §10). It contains no cases yet at M0; the harness that walks these folders arrives with M1. From then on, adding a regression test = adding a folder — no Swift required.

## Case format

Each case is one folder:

```
Corpus/<case_name>/
├── left.txt         # side A, byte-exact, exactly as a user would provide it
├── right.txt        # side B, byte-exact
└── expected.json    # the report the engine must produce for this pair
```

`expected.json` carries the fields the SDD names (verdict, convergence level, change count, formatting count, hunk kinds); the schema is frozen when the M1 harness lands. Working shape:

```json
{
  "profile": "prose",
  "verdict": "formattingOnly",
  "convergenceLevel": "L3",
  "contentChanges": 0,
  "formattingOnly": 1,
  "hunkKinds": []
}
```

- `profile` — expected detected profile: `prose`, `code`, or `plain` (SDD §3.3)
- `verdict` — `identical`, `formattingOnly`, or `changed` (SDD §3.4)
- `convergenceLevel` — lowest ladder level at which the sides become equal, `"L0"` through `"L3"`, or `null` when they never converge (SDD §3.2)
- `contentChanges` / `formattingOnly` — the counts behind the verdict
- `hunkKinds` — ordered hunk kinds for `changed` cases (e.g. `paragraphBoundary` for a split/merge, SDD §6.6); empty otherwise

## Authoring guidance

One phenomenon per case, in the smallest inputs that demonstrate it. Name folders in snake_case after the phenomenon: `crlf_only`, `reflow_paragraph`, `paragraph_split`, `rename_only`. Encode tricky bytes exactly (CRLF, BOM, NBSP, smart quotes) — files are compared as-is, so an editor that "cleans" line endings will quietly destroy a case.

Cases planned for M1 mirror SDD §3.5 and §9: reflow, blank-line runs, CRLF/BOM, NBSP, smart quotes, paragraph split, indentation-only, rename-only, mixed, JSON-ish, minified, emoji, bidi, empty, identical, mostly-rewritten.
