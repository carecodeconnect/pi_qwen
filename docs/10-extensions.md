# Extensions

Extensions are pi's heavier-weight mechanism for adding capabilities. Where [skills](./09-skills.md) are markdown instructions the model loads on demand, extensions are TypeScript modules that register new tools, intercept events, or modify pi's UI. Both are first-class and complementary — pick by capability shape, not preference.

## What an extension is

An extension is an npm package (or local git checkout) that exports one or more entries against the `pi.extensions` field in `package.json`. Each entry is a `.ts` file that pi loads at startup. An extension can:

- **Register a new tool** (e.g. `pi-web-access` registers `web_search`) — the tool gets a structured schema, typed arguments, and a return shape. pi serializes the call in the system prompt at ~50–150 tokens per registered tool ([performance note](./04-tool-calling.md#web-search-pi-web-access)).
- **Hook into events** (e.g. `pi-hooks/checkpoint.ts` snapshots state at the start of every turn).
- **Add slash commands and UI** (e.g. `pi-hooks/permission.ts` adds `/permission`).
- **Wrap or filter built-in tools** (e.g. extensions that redact secrets from tool results before the model sees them).

Pi does not bake in MCP support or web search by design ([Mario Zechner's note in docs/04](./04-tool-calling.md#future-mcp-for-gitgithub)). Everything beyond `read/write/edit/bash` is meant to come from extensions.

## Where extensions install

Two scopes, two source kinds:

|              | Scope | Source kind | Command |
|---|---|---|---|
| Project-local (`./.pi/`) | This repo only | npm package | `pi install -l npm:<pkg>` |
| Project-local | This repo only | Git repo | `pi install -l git:<owner/repo>` |
| Global (`~/.pi/`) | All projects | npm package | `pi install npm:<pkg>` |
| Global | All projects | Git repo | `pi install git:<owner/repo>` |

Project-local is recommended for sandboxing — drops the package into `./.pi/npm/node_modules/`, writes the dependency into `./.pi/settings.json`'s `packages` array, and doesn't touch global Node modules. No sudo, no `/usr/local` permission grief (see [troubleshooting](./06-troubleshooting.md#pi-install-fails-with-eacces-or-ebadengine)).

Uninstall: `pi remove -l npm:<pkg>` for project-local, or just delete `./.pi/`.

Pull updates later: `pi update` (npm sources) or `pi update git:<owner/repo>`.

## What's currently installed in this repo

```json
// .pi/settings.json
{
  "packages": [
    "npm:pi-web-access",
    "npm:pi-hooks"
  ]
}
```

### `pi-web-access`

Web search + content extraction. Registers a `web_search` tool. Zero-config out of the box via Exa's free tier; bring-your-own keys for Tavily / Perplexity / Gemini Web. Full details and config layout in [docs/04-tool-calling.md](./04-tool-calling.md#web-search-pi-web-access).

### `pi-hooks` (bundle of 7 extensions)

[prateekmedia/pi-hooks](https://github.com/prateekmedia/pi-hooks). Single package, seven extensions, toggle individually via `pi config`. Default state varies — see each entry below.

| Extension | What it does | Default | When to enable |
|---|---|---|---|
| `lsp` | Auto-diagnostics at agent end. Feeds type/lint errors back to the model without burning agent turns. | **On** | Always for coding work — biggest quality lift for local models. Use `/lsp` to switch to per-edit diagnostics for tighter feedback. |
| `lsp-tool` | On-demand LSP queries: definitions, references, hover, symbols, signatures. | **On** | Always — composes with `lsp` above. |
| `permission` | Layered guardrails: Minimal (read-only), Low (file edits), Medium (dev commands), High (everything; dangerous commands still prompt). First launch asks which level. | **On**, prompts for level | Always. For sandbox work with local models running unsupervised, **Medium** is the sensible default. Use `/permission` to change. |
| `checkpoint` | Captures repo state at every turn as a git ref. Lets you restore "files + conversation," "conversation only," or "files only" after branching a session. | **On** | When you want to experiment with the same prompt across different models (Qwen vs gpt-oss vs GLM) and roll back cleanly. |
| `ralph-loop` | Subagent loop with exit condition. Adds a `ralph_loop` tool that runs a single or chain task until a condition returns false. | **Off in this repo** (default On) | See "Disabling ralph-loop" note below — needs a stronger model than gpt-oss-20b reliably provides. Re-enable for Sonnet, GLM-4.5-Air, or other agent-tuned models. |
| `repeat` | Re-runs the previous turn with a slash command. | **On** | Quick re-prompt without retyping. |
| `token-rate` | Footer widget showing decode tok/s of the active model. | **On** | Useful for the multi-model sandbox — surfaces the live decode rate when comparing models. |

The seven were not individually selected — they ship together in the `pi-hooks` package. Use `pi config` (interactive TUI) to enable/disable individual extensions in the bundle.

### Disabling individual extensions in a bundle

`pi config` writes the enable/disable state into `.pi/settings.json` using a `-` prefix on the extension path. After disabling `ralph-loop` for this repo:

```json
{
  "packages": [
    "npm:pi-web-access",
    {
      "source": "npm:pi-hooks",
      "extensions": [
        "-ralph-loop/ralph-loop.ts"
      ]
    }
  ]
}
```

The `-` means "exclude this entry from the bundle's default extension list." Every other entry in the package's `pi.extensions` array stays enabled. To re-enable, run `pi config` again and re-check the box, or hand-edit `settings.json` to remove the `-` line.

### Disabling ralph-loop in this repo

Empirical finding from this sandbox: `ralph-loop` is not reliably usable on **gpt-oss-20b**. The tool exposes an optional `agent` parameter that defaults to a built-in `worker` fallback ([upstream README](https://github.com/prateekmedia/pi-hooks/blob/main/ralph-loop/README.md)); gpt-oss-20b doesn't internalize the default and fills in invented values like `agent: "user"`, which triggers a `path argument must be of type string` error inside the extension. Two attempts on 2026-05-14 both ended with the model in a wrong-path loop scanning the filesystem for nonexistent agent definitions instead of recovering.

Reserve `ralph-loop` for models with stronger agent-invocation priors:

- **Sonnet / Claude** — works cleanly.
- **GLM-4.5-Air** — untested but likely fine; agent-tuned weights.
- **Qwen3-Coder-30B-A3B** — untested; similar capability class to gpt-oss-20b, so probably similar failure mode.

For day-to-day work driven by local models in the ~3-4 B-active class, leave `ralph-loop` disabled. The other six pi-hooks extensions don't have this issue — they're all "tool wrappers" or "event hooks" rather than "subagent dispatch," which is the abstraction the smaller models struggle with.

## Skill vs. extension recap

Same table that appears in [docs/09-skills.md](./09-skills.md#when-to-choose-a-skill-vs-an-extension), repeated here so you don't have to cross-reference:

- **Skill** — instructions + helper scripts the model invokes via `bash`. Fast to write, no build step. Best for repeatable procedures (release checklist, codebase survey, lint-fix loop).
- **Extension** — when you need a *new tool type* with structured arguments and typed return shape. Heavier — TypeScript module, npm install, costs ~50–150 prompt tokens per registered tool. Best for capabilities that wrap external services (web search, LSP, browser automation) or modify pi's event loop.

A useful heuristic: if your idea could be a `bash` one-liner with a prompt around it, write a skill. If it needs to *react* to pi's state (intercept tool calls, run on every turn, add a slash command), write an extension.

## Writing your own extension

Minimum surface:

```typescript
// my-extension.ts
import { defineExtension, type ToolDefinition } from "@earendil-works/pi-coding-agent";

const myTool: ToolDefinition = {
  name: "my_tool",
  description: "What this tool does — shown to the model.",
  parameters: { /* JSON Schema */ },
  async run({ args }) {
    // implementation
    return { content: "result" };
  },
};

export default defineExtension({
  tools: [myTool],
  // optional: hooks, slashCommands, ui components
});
```

`package.json` points at it:

```json
{
  "name": "my-pi-extension",
  "version": "0.1.0",
  "pi": {
    "extensions": ["./my-extension.ts"]
  }
}
```

Then install: `pi install -l git:github.com/<you>/<repo>` (or publish to npm and use `pi install -l npm:<pkg>`).

For richer examples, read the source of [`pi-web-access`](https://github.com/nicobailon/pi-web-access) (registers a tool) and [`prateekmedia/pi-hooks`](https://github.com/prateekmedia/pi-hooks) (mixes tools, hooks, slash commands, and UI).

## Extension repositories

Three upstream catalogs to draw from — same three the [skills doc](./09-skills.md#skill-and-extension-repositories) points at, because most "skills" catalogs also list extensions:

- [qualisero/awesome-pi-agent](https://github.com/qualisero/awesome-pi-agent) — meta-catalog of extensions, skills, tools, prompt templates. Start here for discovery.
- [anthropics/skills](https://github.com/anthropics/skills) — official catalog. Most entries are skills, but `mcp-builder` and `skill-creator` straddle the line.
- [badlogic/pi-skills](https://github.com/badlogic/pi-skills) — community skills mostly, but a few have companion extensions.

## Security note

> Extensions execute TypeScript in pi's process. They can call any tool, read any file pi can read, and make arbitrary network requests. Review the source before installing third-party extensions.

`pi install -l` is preferable to global install for this reason: a project-local extension is scoped to one repo's session, so a compromised one can't reach into unrelated work. Even so, read the entry-point `.ts` files (and at least skim `package.json`'s dependencies) before trusting a new extension.

The `pi-hooks/permission` extension also helps here — running with permission level **Medium** means even a compromised extension can't `rm -rf /` without a confirm prompt.
