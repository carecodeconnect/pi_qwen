---
name: mermaid
description: "Guide for creating, formatting, and validating Mermaid diagrams. Use when the user asks to draw, format, lint, or validate a Mermaid diagram."
---

# Mermaid Skill

Two tools for working with Mermaid diagrams: `format.sh` (cargo-fmt equivalent) and `validate.sh` (cargo-check equivalent). The intended loop is **format → validate → fix → revalidate** until both pass cleanly.

## Prerequisites

- Node.js + npm (for `npx`).
- `validate.sh` first run downloads a headless Chromium via Puppeteer (~100 MB). If Chromium is missing, set `PUPPETEER_EXECUTABLE_PATH`.
- `format.sh` first run downloads `mermaid-formatter` (~1 MB).

## Tools

### Validate (parser + renderer)

```bash
./tools/validate.sh diagram.mmd [output.svg]
```

- Parses and renders the Mermaid source via `mmdc` (`@mermaid-js/mermaid-cli`).
- Non-zero exit = invalid Mermaid syntax; the parser points at the offending line/column.
- Prints an ASCII preview using `beautiful-mermaid` (best-effort; not all diagram types are supported).
- If `output.svg` is omitted, the SVG is rendered to a temp file and discarded.

### Format (normalize whitespace + structure)

```bash
./tools/format.sh diagram.mmd            # write in place
./tools/format.sh --check diagram.mmd    # diff against formatted; exit 1 if changes needed
```

- Uses `mermaid-formatter`'s `mermaidfmt` CLI under the hood.
- Normalizes indentation, collapses consecutive blank lines, spaces sequence-diagram arrows.
- Not as strict as `cargo fmt` — Mermaid's ecosystem lacks a universally-accepted canonical formatter — but it's a consistency helper.
- `--check` mode is CI-friendly: prints a diff and exits 1 if the file needs reformatting.

## Workflow

1. **If the diagram will live in Markdown**: draft it in a standalone `diagram.mmd` first (the tool only validates plain Mermaid files).
2. Write/update `diagram.mmd`.
3. Run `./tools/format.sh diagram.mmd` to normalize structure.
4. Run `./tools/validate.sh diagram.mmd`.
5. If the validator fails, fix the offending line/column and revalidate. **Do not give up on the first failure** — iterate.
6. Once both pass, copy the Mermaid block into your Markdown file.

## Common syntax pitfalls

The validator catches these; here are the most common:

- **Unquoted parens, colons, or quotes inside node labels** — `serve[qwen-serve (terminal 1)]` fails; wrap in `"..."`: `serve["qwen-serve (terminal 1)"]`.
- **Angle brackets** — `<` and `>` need HTML entities: `&lt;` and `&gt;`. Or substitute words like `MODEL`/`any` to avoid them entirely.
- **Two consecutive arrows** — `A --> --> B` is invalid; needs a node between them.
- **Indentation matters in `subgraph` blocks** — close with `end` on its own line.
