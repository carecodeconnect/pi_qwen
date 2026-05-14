# Third-party skills

This directory contains pi skills vendored from external repositories. Locally-authored skills (e.g. `swap-model`, `git-github`) are not listed here.

## Vendored from [mitsuhiko/agent-stuff](https://github.com/mitsuhiko/agent-stuff) (Apache License 2.0)

- `mermaid/` — Mermaid diagram validation via the official Mermaid CLI.
- `tmux/` — Programmatic tmux control for interactive CLIs (REPLs, debuggers, watch processes).
- `uv/` — uv quick reference for running scripts, managing dependencies, and inline script metadata.

Upstream commit: shallow clone of `main` branch on 2026-05-14.

Apache 2.0 license: see <https://www.apache.org/licenses/LICENSE-2.0>. Notable terms:

- Attribution required (this file).
- Modifications must be marked.

### Modifications

- `mermaid/SKILL.md` (2026-05-14): expanded to document the iterate-and-validate workflow, common syntax pitfalls, and a section on the new `format.sh`. Original upstream version was validation-only.
- `mermaid/tools/format.sh` (2026-05-14): added. Wraps `mermaidfmt` (`mermaid-formatter` npm package) to provide a `cargo fmt`-equivalent. Original upstream had no formatter, only `validate.sh`.
