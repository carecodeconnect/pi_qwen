# Skills

Skills are pi's lighter-weight alternative to extensions for adding capabilities. Where extensions are TypeScript modules that register new tools, skills are plain markdown directories the model loads on demand — closer to "Claude Code skills" or "agent prompt packs" than to code.

## What a skill is

A skill is a directory containing a `SKILL.md` file with required `name` / `description` frontmatter. pi scans the skill locations at startup and lists each name+description in the system prompt; the model loads the full `SKILL.md` on demand via `read` when a task matches, or you can force-load with `/skill:<name>`. This is progressive disclosure — descriptions are always in context, full instructions only when needed.

pi implements the [Agent Skills standard](https://agentskills.io/specification), warning about violations but remaining lenient.

The `librarian` skill that pi shows in the startup banner is bundled inside the pi npm package itself; it's how pi self-documents ("Pi can explain its own features and look up its docs"). You don't need to install it.

## Where pi looks for skills

Per pi's bundled docs (`/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/docs/skills.md`), in priority order:

| Scope | Location | Notes |
|---|---|---|
| Global | `~/.pi/agent/skills/` | All projects, root-level `.md` files OR directories with `SKILL.md`. |
| Global | `~/.agents/skills/` | Cross-harness shared dir. Root `.md` files ignored — must be `SKILL.md` dirs. |
| Project | `.pi/skills/` | Scoped to the current repo. |
| Project | `.agents/skills/` | Walked up to git root (or filesystem root if not in a repo). |
| Package | npm package with `skills/` dir or `pi.skills` entry in `package.json` | Bundled with installed extensions. |
| Settings | `"skills": [...]` array in `settings.json` | Explicit paths to files or dirs. |
| CLI | `--skill <path>` (repeatable) | Additive, works even with `--no-skills`. |

Disable auto-discovery entirely with `--no-skills`. Name collisions across locations warn and keep the first one found.

## Adding a project-local skill (recommended for this repo)

Mirrors how `pi-web-access` is wired in this repo — scoped to the project, no global state.

```bash
mkdir -p .pi/skills/my-skill
$EDITOR .pi/skills/my-skill/SKILL.md
```

Minimum content for `SKILL.md`:

```markdown
---
name: my-skill
description: One-sentence summary of what this skill does and when to use it. Be specific — the description is what determines when the agent loads the skill.
---

# My Skill

## Usage

Step-by-step instructions for the model. Relative paths reference scripts/assets in this directory.
```

Frontmatter rules ([full spec](https://agentskills.io/specification#frontmatter-required)):

- `name` (required) — 1–64 chars, lowercase `a-z`, digits, hyphens. Must match the parent directory name. No leading/trailing or consecutive hyphens.
- `description` (required) — max 1024 chars. Skills with no description are silently dropped.
- **YAML gotcha:** don't put unquoted colons inside `description` or `name` values — pi's YAML parser treats an embedded `:` as a nested mapping and rejects the skill with `Nested mappings are not allowed in compact mappings`. Use an em dash, parentheses, or wrap the whole value in double quotes.
- Optional: `license`, `compatibility`, `metadata`, `allowed-tools`, `disable-model-invocation` (hides from system prompt; only invokable via `/skill:name`).

Relaunch pi — the skill shows up under `[Skills]` in the startup banner. Force-load it with `/skill:my-skill` (with optional args: `/skill:my-skill some args` appends `User: some args` to the loaded content).

## Adding a global skill

Same structure, different location:

```bash
mkdir -p ~/.pi/agent/skills/my-skill
$EDITOR ~/.pi/agent/skills/my-skill/SKILL.md
```

Available across every project. Use this for personal workflows you want everywhere (commit message style, code-review checklist, etc.).

## Reusing Claude Code / Codex skills

Pi can load skills from other harnesses by pointing at their directories from `settings.json`:

```json
{
  "skills": [
    "~/.claude/skills",
    "~/.codex/skills"
  ]
}
```

For project-scoped Claude Code skills, put this in `.pi/settings.json`:

```json
{
  "skills": ["../.claude/skills"]
}
```

## Worked example: `brave-search`

Taken from pi's bundled skills docs — a complete real skill with a helper script.

```
brave-search/
├── SKILL.md
├── search.js
└── content.js
```

`SKILL.md`:

````markdown
---
name: brave-search
description: Web search and content extraction via Brave Search API. Use for searching documentation, facts, or any web content.
---

# Brave Search

## Setup

```bash
cd /path/to/brave-search && npm install
```

## Search

```bash
./search.js "query"              # Basic search
./search.js "query" --content    # Include page content
```

## Extract Page Content

```bash
./content.js https://example.com
```
````

The model `read`s `SKILL.md`, sees the bash commands, and emits `bash` tool calls against the helper scripts. No new tool types are registered — skills compose with pi's built-in `read/write/edit/bash`.

## When to choose a skill vs. an extension

- **Skill** — workflows expressible as instructions + helper scripts the model invokes via `bash`. Faster to write, no TypeScript build, no Node deps to manage. Best for repeatable procedures (release checklist, codebase-survey routines, lint-fix loops).
- **Extension** — when you need to register a *new tool type* with structured arguments and typed return shapes (like `pi-web-access` adding `web_search`). Heavier — TypeScript module, npm install, costs ~50–150 prompt tokens per registered tool ([performance note](./04-tool-calling.md#web-search-pi-web-access)).

## Skill repositories

Two upstream collections worth pointing at via `settings.json`:

- [anthropics/skills](https://github.com/anthropics/skills) — document processing (docx, pdf, pptx, xlsx), web development.
- [badlogic/pi-skills](https://github.com/badlogic/pi-skills) — web search, browser automation, Google APIs, transcription.

## Security note

> Skills can instruct the model to perform any action and may include executable code the model invokes. Review skill content before use.

Same trust posture as installing extensions: read the `SKILL.md` and any referenced scripts before dropping a third-party skill into `.pi/skills/` or `~/.pi/agent/skills/`.
