# Tool calling

pi needs the model to emit **structured tool calls**, not text. This page covers the template wiring that makes that work, the verification flow, and the extensions that add capabilities beyond pi's built-in `read/write/edit/bash` tools.

## Why the chat template matters

By default, the Unsloth Q5_K_M Qwen3-Coder-30B GGUF ships with an embedded chat template that has a tool-call bug: the model produces inner `<function=...>` blocks without the outer `<tool_call>` wrapper Qwen expects. llama-server then can't parse those back into the `tool_calls` field, pi sees raw text, no tools execute, and the agent appears to hallucinate that it's running commands.

The fix is to load Qwen's official chat template explicitly via `--chat-template-file`. That's what `fetch-template` downloads and `qwen-serve` wires in.

Other models have different stories:

- **gpt-oss-20b** — chat template is correct in the GGUF; `--jinja` alone is enough.
- **GLM-4.5-Air** — Unsloth's GGUF embeds a corrected template; `--jinja` alone is enough.
- **Qwen3-Coder-Next-80B-A3B** — same bug as Qwen3-Coder-30B; same fix (fetch upstream template via the env-var override on `fetch-template`).

## Verifying the template is loaded

After starting `qwen-serve` (or `qwennext-serve`):

```bash
curl -s http://127.0.0.1:8080/props | python3 -c "
import sys, json
d = json.load(sys.stdin)
ct = d.get('chat_template','')
print('template loaded:', bool(ct), 'length:', len(ct))
print('first line:', ct.split(chr(10))[0])
"
```

For Qwen3-Coder, if the first line is `{% macro render_extra_keys(json_dict, handled_keys) %}` you've got Qwen's official template. If it starts with an Unsloth copyright header, the override didn't take — re-run `fetch-template` and re-check the file path in the serve script.

## End-to-end check

`tool-call-test` (see [docs/03-serving.md](./03-serving.md#tool-call-test)) defines a `get_weather` tool and verifies the model emits structured `tool_calls`. Run it before trusting any new model:

```bash
ALIAS=qwen3-coder-30b-a3b   tool-call-test
ALIAS=local-qwen3-coder-next tool-call-test
ALIAS=local-gpt-oss-20b     tool-call-test
ALIAS=local-glm-4.5-air     tool-call-test
```

Smoke test inside pi: ask `explain the purpose of this codebase` from inside this repo. You should see pi actually execute `find` and `read README.md` as tool calls (rendered as `$ find ...` and `read README.md` blocks in the TUI), not raw `<function=bash>` XML.

## Extending pi with custom tools

By default pi gives the model four tools: `read`, `write`, `edit`, `bash`. pi deliberately doesn't bake in MCP support or web search — the design choice is to keep the core minimal and let users add capabilities via extensions (TypeScript modules) or skills.

Extension packages can be installed two ways:

- **Project-local** (`pi install -l <source>`) — lands in `./.pi/`, scoped to the current repo. No sudo, no global Node modules touched. Survives `pi update`. Recommended for sandboxing.
- **Global** (`pi install <source>`) — lands in npm's global prefix. Affects every project. Trips on the macOS root-owned `/usr/local` problem unless Node was installed via Homebrew or nvm (see [troubleshooting](./06-troubleshooting.md#pi-install-fails-with-eacces-or-ebadengine)).

## Web search: `pi-web-access`

[nicobailon/pi-web-access](https://github.com/nicobailon/pi-web-access) adds a `web_search` tool plus content extraction. Zero-config out of the box using Exa's free tier; bring-your-own keys for Tavily / Perplexity / Gemini Web.

Project-local install (what this repo uses):

```bash
# From the repo root
pi install -l npm:pi-web-access
```

That writes `./.pi/settings.json` with `{"packages": ["npm:pi-web-access"]}` and installs the dependency tree under `./.pi/npm/node_modules/`. No global state changed. To uninstall: `pi remove -l npm:pi-web-access` or just delete `./.pi/`.

Global config (optional, shared across projects) lives at `~/.pi/web-search.json`:

```json
{
  "exaApiKey": "exa-...",
  "perplexityApiKey": "pplx-...",
  "geminiApiKey": "AIza...",
  "allowBrowserCookies": true
}
```

Every field is optional. Env vars `EXA_API_KEY` / `PERPLEXITY_API_KEY` / `GEMINI_API_KEY` / `PI_ALLOW_BROWSER_COOKIES=1` override file values. On macOS, enabling browser cookies may trigger a Keychain dialog.

**Verify the tool is registered** by launching pi from this repo and asking it something that requires search:

```bash
qwen-serve                              # or any other *-serve
# in another terminal:
cd /path/to/pi_sandbox
pi --model qwen3-coder-30b-a3b "what is the latest version of llama.cpp?"
```

You should see pi emit a `web_search(query: "...")` call in the TUI before answering. If it falls back to "I don't have access to current information," the extension didn't load — check `pi list` (should show `npm:pi-web-access`) and that you launched pi from a directory whose `.pi/settings.json` references it.

**Performance note.** Tool definitions cost prompt tokens (~50–150 tokens per tool). On gpt-oss-20b that's barely felt; on GLM-Air with its 161 tok/s prefill, several tools sum to a noticeable bit of latency. Start with just `web_search` and add more only when needed.

## Future: MCP for git/GitHub

pi doesn't speak MCP natively (Mario Zechner's design call: MCP servers are overkill for most use cases and burn context). But there's a community adapter — [nicobailon/pi-mcp-adapter](https://github.com/nicobailon/pi-mcp-adapter) — that lets pi consume any MCP server via a ~200-token proxy.

Planned for a future iteration: wire up an MCP server for git/GitHub actions (clone, commit, PR review, etc.) via the adapter, so the local model can do code-review and PR-management workflows without leaving pi. See [Onetool Pi](https://mcpmarket.com/server/onetool-pi) and the [awesome-pi-agent](https://github.com/qualisero/awesome-pi-agent) catalog for the broader MCP ecosystem.

Not wired up yet — listed here so the design intent is recorded.
