# TODO — `install/skills.sh`

Add an installer that wires a curated set of skills into the pi agent, mirroring the pattern of the existing model installers (`install/gpt-oss-20b.sh`, `install/qwen3-coder-30b.sh`, etc.).

## Why

Per [`09-skills.md`](./09-skills.md) skills must already exist in one of the discovery locations (`~/.pi/agent/skills/`, `~/.agents/skills/`, `.pi/skills/`, …) before pi will load them. Today there is no scripted way to bootstrap a fresh machine with the skills we actually want — every install is manual `mkdir` + `$EDITOR`. An `install/skills.sh` would make a freshly-provisioned X270 or M1 Max usable end-to-end after a single command, matching the model-install ergonomics.

## Shape

- [ ] `install/skills.sh` — idempotent shell script:
  - Default target: `~/.pi/agent/skills/` (global, all projects). Allow `SKILLS_DIR` env override for `.pi/skills/` project installs.
  - Curated default set (all API-key-free, matches the project's offline / no-cloud posture):
    - **`skill-creator`** (`anthropics/skills`) — helps author new project skills faster; high leverage given the repo's pattern of hand-writing skills (`git-github`, `swap-model`, `mermaid`, `tmux`, `uv` already live under `.pi/skills/`).
    - **`mcp-builder`** (`anthropics/skills`) — extend pi via MCP without writing a full TypeScript extension (the heavier option flagged in [`09-skills.md`](./09-skills.md)).
    - **`pdf`** (`anthropics/skills`) — local-only PDF reading for model cards, papers, llama.cpp docs.
  - Optional set behind `--with-online` (require network and/or API keys, so off by default):
    - **`brave-search`** (`badlogic/pi-skills`) — needs `BRAVE_API_KEY`; violates the README's "no API keys" pitch unless the user opts in.
    - **`browser-tools`** (`badlogic/pi-skills`) — local headless browser; no key but heavier deps.
  - Explicitly **skip** (poor fit for a local-coder-agent sandbox): `docx` / `pptx` / `xlsx` / `slack-gif-creator` / `brand-guidelines` / `internal-comms` / `canvas-design` / `theme-factory` / `gccli` / `gdcli` / `gmcli` / `transcribe` / `youtube-transcript` / `claude-api` / `vscode`.
  - For each skill: fetch source (git clone / curl tarball / copy from a vendored `skills/` dir in this repo), validate `SKILL.md` frontmatter (`name`, `description`, `name` matches dir), skip if already present unless `--force`.
  - Print a summary listing installed skills + the banner line pi will show on next launch.
- [ ] `install/all-models.sh` — add an optional `--with-skills` flag that chains `install/skills.sh` after the model installs.
- [ ] Document in [`09-skills.md`](./09-skills.md) under a new *Bulk install* section, pointing at `install/skills.sh`.
- [ ] Decide where the source-of-truth skill content lives — vendored in this repo under `skills/<name>/SKILL.md`, or pulled from upstream repos. Vendoring is simpler and matches how models are pinned by GGUF filename.

## Acceptance

Running `install/skills.sh` on a fresh machine results in `pi` showing the expected skills under `[Skills]` in its startup banner, with no manual file editing.
