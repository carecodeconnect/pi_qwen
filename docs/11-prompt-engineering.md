# Prompt engineering

Evidence-based tips for getting useful work out of the four local models in this repo, with specifics for prompting via pi's skills and extensions. Mixes upstream guidance (model vendor docs), community recipes, and empirical findings from this sandbox's own test runs.

## TL;DR — pick a model that fits the task shape

| Task shape | Best model in this repo | Why |
|---|---|---|
| Multi-step agentic workflows (skills, tool chains, iterate-on-failure) | **GLM-4.5-Air** | Agent-tuned (Z.ai's "ARC" training — Agentic/Reasoning/Coding fused). Empirically the only local model that recovers cleanly from tool-call failures in our test runs. |
| Single-file code edits, focused refactors | **Qwen3-Coder-30B-A3B** | Coder-specialized. Strong on syntactic correctness. Untested on long agent loops in this repo. |
| Survey-style Q&A, structured output, reasoning | **gpt-oss-20b** | Fastest decode (~60 tok/s). Reasoning-tuned. **Avoid for skill-driven multi-step work** — empirically gets stuck in meta-loops. |
| Long-context refactors, multi-file changes | **Qwen3-Coder-Next-80B-A3B** | Prefill is nearly flat with context (only 6% drop pp512→pp8192 vs 31% for the 30B). Same active params as 30B. |

The choice matters more for **agentic** prompts than for one-shot prompts. For a one-shot "explain this function," all four work. For "iterate this skill until it passes," only GLM-Air and (cloud) Sonnet handle it reliably in our testing.

## General coding-agent prompting rules

These apply across all four models and align with what Mario Zechner (pi's author) recommends — pi deliberately ships a minimal system prompt and four built-in tools (`read`, `write`, `edit`, `bash`) on the theory that frontier-RL'd models already know how to be coding agents. Your prompt's job is to specify the task, not to teach the agent what an agent is.

1. **Be specific about success criteria.** "Make this faster" loses to "reduce p99 latency below 50 ms; measure with `bench/throughput.sh`; don't change the public API." A coding agent needs the goal, the file context, constraints, expected output, and a verification target.
2. **Say what *not* to do.** "Don't refactor unrelated code" prevents the model from wandering. Especially important on weaker local models.
3. **Provide file context inline when small enough.** `read foo.rs` then "now fix the bug on line 42" outperforms "find and fix the bug in the codebase."
4. **Imperative > suggestive.** "Write a function that…" beats "Could you maybe write a function that…" — local models in particular weight imperative phrasing more heavily.
5. **Lower temperature for production-ish work.** Qwen3-Coder docs recommend `temperature=0.2` for deterministic outputs; the `*-serve` scripts in this repo already encode the right per-model recipe.

## Model-specific tips

### Qwen3-Coder-30B-A3B-Instruct (default)

**Sampler recipe** (already in `qwen-serve`): for thinking mode, `temperature=0.6 top_p=0.95 top_k=20 min_p=0`. Per Qwen's docs, do **not** use greedy decoding — it can produce repetition loops.

**Strengths from vendor docs and community recipes:**
- Structured output (JSON, tool calls). Use a system message like `You return ONLY valid JSON. No commentary.` and the model holds the format reliably.
- Iterative debugging — Qwen3-Coder is explicitly tuned for "agentic capabilities to iteratively debug and optimize."
- Style guidance honored — say "use idiomatic Rust with `Result` over `Option`" and it'll follow.

**Empirical caveats from this repo:**
- We hit a tool-call template bug on first install — the bundled chat template emits `<function=...>` instead of `<tool_call>...`. Fixed by loading Qwen's official template via `--chat-template-file` (the `fetch-template` script handles this). If your tool calls render as text instead of executing, that's the symptom — see [`docs/04-tool-calling.md`](./04-tool-calling.md).

### gpt-oss-20b

**Chat template:** uses OpenAI's [Harmony response format](https://github.com/openai/harmony), which standardizes channels (chain-of-thought, tool preambles, final response) and reasoning effort levels (`low`/`medium`/`high`). The Unsloth GGUF embeds a correct template, so `--jinja` alone wires it up. **Do not run gpt-oss without Harmony** — the model won't behave correctly.

**Reasoning effort:** unique to this model in our set. You can set it via system prompt (e.g., `Reasoning: high`) or via the Harmony channels — useful for hard reasoning tasks where you'd accept slower decode for better answers.

**Strengths:**
- Fastest decode in our set (~60 tok/s on M1 Max).
- Strong on focused Q&A and survey tasks (e.g., the `web_search` integration tested cleanly).
- Clean tool-call hygiene on simple, single-shot tool calls.

**Empirical caveats — these are real and reproducible in this sandbox:**
- **Skill meta-loops.** First-pass attempts at using a skill triggered the model searching for an "invocation API" instead of just following the procedure. Fixed by anchoring `git-github/SKILL.md` with an explicit "this is instructions you execute via bash, not a function to invoke" header. See `.pi/skills/git-github/SKILL.md` lines 5-21.
- **Doesn't iterate on tool failures.** Wrote broken Mermaid syntax, ran `validate.sh`, got a parser error, then *gave up* and pasted the broken output to the user. Counter-anchor: include "Do not stop after the first parser error — read it and fix" in your prompt or skill.
- **Invents API parameters.** With `ralph_loop` (now disabled in this repo), gpt-oss-20b filled in `agent: "user"` for an optional parameter whose default is the built-in `worker`. Counter-anchor: when prompting tools with optional params, explicitly say "leave optional parameters at their defaults unless I specify otherwise."
- **Doesn't sanity-check its own output before declaring success.** When generating Mermaid syntax it didn't read its own output to catch unquoted parens — wrote it, validated it (failed), then gave up. Counter-anchor: tell it explicitly to validate.

### GLM-4.5-Air

**Sampler recipe** (already in `glmair-serve`): `temperature=0.6 top_p=0.95`. Per Z.ai's GLM-4.5 blog.

**Strengths from vendor docs:**
- Function-calling accuracy benchmarked at 90.6% — highest in our set.
- "Native fusion of reasoning, coding, and agent abilities" — explicitly trained on multi-turn agent tasks in isolated container environments against Claude/Kimi/Qwen.
- Z.ai claims reduced prompt-engineering overhead for tool invocation, web browsing, software engineering, and front-end. In practice this means you can be terser with GLM-Air than with gpt-oss-20b for the same task.
- Already proven in this sandbox: passed `tool-call-test` first try; the `swap-model` skill demo (until the self-disconnect edge case) was clean.

**Caveats:**
- Slowest decode in the set (~20 tok/s) — ~12 B active params (vs ~3 B for the others). Bandwidth-bound on Apple Silicon. **Speed cost vs. reliability gain is the trade-off.**
- Needs the Metal wired-memory cap raised (see `install/glm-4.5-air.sh` and `docs/06-troubleshooting.md`).
- KV cache budget is tight at this model size — `glmair-serve` defaults `CTX=32768` rather than 131k.

### Qwen3-Coder-Next-80B-A3B-Instruct

Same architecture and sampler as the 30B variant. The differentiator is **prefill behavior under long context**: it loses only ~6% throughput from pp512 to pp8192 (vs the 30B's 31% drop). So at long contexts the gap narrows substantially. Prefer for: multi-file refactors, reading large codebases, code review on diffs that don't fit in 32k.

Decode is ~37% slower than the 30B (~32 tok/s vs ~51 tok/s) — fine if context dominates, painful if turn count does.

## Prompting via pi

Pi's design philosophy is **minimal system prompt + four built-in tools + capability-via-skills-or-extensions**. Your prompt interacts with all three.

### Skills

Skills are markdown procedures. They're scanned at pi startup; their `name + description` go into the system prompt; the full `SKILL.md` loads on demand when the agent decides the task matches.

**Three ways to invoke:**

1. **Implicit (recommended for ergonomic flow):** phrase the prompt so the skill description matches. The agent picks up the cue and loads the skill itself.
   - `commit these changes` → triggers `git-github`
   - `swap to gpt-oss-20b` → triggers `swap-model`
   - `draw a flowchart of …` → triggers `mermaid`
2. **Explicit force-load:** `/skill:<name> [args]`. Loads `SKILL.md` regardless of whether the description matched. Use when you need certainty (e.g. demoing) or when the description didn't fire.
3. **Verbatim cue:** include the skill name in the prompt body (e.g. "use the **mermaid** skill to …"). Less reliable than `/skill:`, more reliable than pure description matching.

**Writing prompts that work with skills:**

- Reference the *outcome* the skill produces, not the skill's mechanics. "Commit these changes with a good message" works better than "use git add then git commit."
- For multi-procedure skills (like `git-github` with Procedures A/B/C), say which one. "Open a pull request" → Procedure B; "create an issue" → Procedure C.
- For weak local models, add **"don't stop after the first failure"** when the skill involves an iterate loop (e.g., `mermaid` format/validate/fix). Empirically this is the single biggest delta for gpt-oss-20b vs. failing.

**Writing skills that work for local models** (you'll write some — see `docs/09-skills.md`):

- Anchor early with "this is instructions you execute via bash, not a function to invoke." Weak models otherwise hunt for an invocation API. (Lesson from our `git-github` first iteration.)
- Map user intent → procedure explicitly. Trigger phrases listed in plain text, not implied.
- List failure modes the model should recognize. "If you see X, do Y" beats "handle errors appropriately."
- YAML frontmatter gotcha: **no unquoted colons** in `description` or `name`. Use em dashes or quote the value. (Real bug we hit.)

### Extensions

Extensions register actual tools the agent calls. The agent picks them up the same way as `read`/`write`/`edit`/`bash` — by the tool description in the system prompt.

For this repo's currently-installed set:

- **`web_search` (from `pi-web-access`)** — triggers on prompts that need current information. "What's the latest version of llama.cpp?" → triggers. "Refactor this function" → does not. The model decides; no special syntax needed.
- **LSP (`lsp` + `lsp-tool` from `pi-hooks`)** — `lsp-tool` is a structured tool the model calls; the `lsp` hook fires *automatically* at agent end. To explicitly query symbols/definitions/diagnostics, say `use the LSP to <verb> <subject>`. Cold-start on Rust projects is slow (`mistralrs` dep means 1–5 min first-time index); subsequent calls are instant.
- **`permission` (from `pi-hooks`)** — not a tool but a gate. If pi refuses an action, the cause is usually permission-level. `/permission` to bump (Minimal → Low → Medium → High). For sandbox work, **Medium** is the sensible default.
- **`checkpoint` (from `pi-hooks`)** — automatic, no prompting needed. Runs every turn.
- **`token-rate` (from `pi-hooks`)** — passive footer widget.

## Empirical findings from this sandbox

These are repo-specific observations from actual test runs. Treat as more authoritative than the vendor blog claims because they came from running the actual GGUFs in pi with our actual skills.

| Finding | Models affected | Counter-anchor |
|---|---|---|
| Skills are searched for an "invocation API" | gpt-oss-20b | Add "this is procedural instructions, not a function" to the SKILL.md anchor section. |
| Doesn't iterate on tool failures | gpt-oss-20b | Explicit "do not stop after the first error — read it and fix" in prompt or skill. |
| Invents values for optional tool parameters | gpt-oss-20b | "Leave optional parameters at defaults unless I specify." |
| `ralph_loop` agent abstraction is uninternalized | gpt-oss-20b | Disabled in `.pi/settings.json` for this repo. Reserve `ralph_loop` for Sonnet or GLM-Air. |
| `serve-stop` while pi is hosted on the same model self-disconnects | All local models | The `swap-model` skill's preflight check guards against this. Don't drive a swap from the model being swapped away from. |
| Cold-start LSP indexing on Rust returns empty rather than "still indexing" | Independent of model | If `lsp-tool` returns nothing on the first call, wait 30–60 s and retry; don't run `cargo check` to "fix" it (which gpt-oss-20b did). |

## Reasoning levels per model

Pi shows a `low/medium/high` reasoning slider in the footer (and via `/thinking`) for every model whose `models.json` entry has `"reasoning": true`. The control is pi's `defaultThinkingLevel` (from `~/.pi/agent/settings.json`), but **whether the model actually honors it depends on the model's native support.**

| Model | Native support | What low/medium/high actually does |
|---|---|---|
| **gpt-oss-20b** | Native, via Harmony's `reasoning_effort` channel | Direct 1:1. Real latency + quality difference. `high` for hard logic; `low` for quick edits. Can also be set per-prompt by including `Reasoning: high` in the system message. |
| **GLM-4.5-Air** | Native (Z.ai's ARC training fuses reasoning into the base model) | Maps to "thinking budget" — higher = longer chain-of-thought before the response. Real quality gain on hard tasks, real decode-time cost (and GLM-Air is already the slowest decoder). |
| **Qwen3-Coder-30B-A3B** | Limited — the Qwen3-Coder branch is Instruct-only, not the hybrid Qwen3 base that has `/think` / `/no_think` toggles | The slider is largely decorative for this model. Behavior is similar at low/medium/high. |
| **Qwen3-Coder-Next-80B-A3B** | None — `models.json` has it `"reasoning": false`. Slider hidden. | No effect. |

**To change it:**

- **Per session:** `/thinking` slash command inside pi.
- **Global default:** edit `~/.pi/agent/settings.json` → `"defaultThinkingLevel": "low" | "medium" | "high"`.
- **Per prompt (gpt-oss-20b only):** include `Reasoning: high` at the top of your message; Harmony honors it as a channel-level override.

**Practical recommendation:**

- Keep the global default at `medium` — sensible for most agentic work.
- Bump to `high` for hard reasoning / multi-step planning, with caveats: cheap on gpt-oss-20b (fast decode), expensive on GLM-Air (slow decode but uses the budget well).
- Don't bother tuning for Qwen3-Coder — slider is decorative.

## Sampler recipes per model

| Model | Sampler | Source |
|---|---|---|
| Qwen3-Coder-30B-A3B | `temp=0.6 top_p=0.95 top_k=20 min_p=0` | [Qwen3 docs](https://qwen3lm.com/qwen3-prompt-engineering-structured-output/) |
| Qwen3-Coder-Next-80B-A3B | same as 30B | Qwen3 docs |
| gpt-oss-20b | model defaults; Harmony channels control verbosity / reasoning effort | [OpenAI Harmony docs](https://github.com/openai/harmony) |
| GLM-4.5-Air | `temp=0.6 top_p=0.95` | [Z.ai GLM-4.5 blog](https://z.ai/blog/glm-4.5) |

The `scripts/*-serve` scripts in this repo already encode the right per-model recipe. Don't override unless you know what you're changing.

## Sources

- [Qwen3 Coder: Prompt Engineering Guide for Structured Output](https://qwen3lm.com/qwen3-prompt-engineering-structured-output/) — coder-specific tips on system prompts, structured output, sampler recipes.
- [OpenAI Harmony Response Format (cookbook)](https://cookbook.openai.com/articles/openai-harmony) — gpt-oss requires this format; explains channels, reasoning effort, tool preambles.
- [openai/harmony (GitHub)](https://github.com/openai/harmony) — renderer/spec for the Harmony format.
- [Z.ai GLM-4.5 blog](https://z.ai/blog/glm-4.5) — vendor description of GLM-4.5's ARC (Agentic, Reasoning, Coding) training and benchmark methodology vs. Sonnet/Kimi/Qwen.
- [A Technical Deep Dive into GLM-4.5 (Medium)](https://medium.com/data-science-in-your-pocket/a-technical-deep-dive-into-glm-4-5-agentic-reasoning-and-coding-arc-1fffd98803e4) — independent write-up; covers function-calling accuracy claims.
- [Mario Zechner's pi-coding-agent post](https://mariozechner.at/posts/2025-11-30-pi-coding-agent/) — pi's design rationale: minimal system prompt, four tools, capability-via-skills.
- [pi.dev skills docs](https://pi.dev/docs/latest/skills) — official skill format, discovery rules, `/skill:name` invocation.
- [How to roll your own local AI coding agents — The Register (2026)](https://www.theregister.com/2026/05/02/local_ai_coding_agents/) — broader landscape of local-model coding agents; useful framing for when local is "good enough."
- [Running Pi with Local LLMs — Medium](https://medium.com/@tolgaeren/running-pi-with-local-llms-c596aa14b062) — practical write-up of pi with Qwen on local hardware.

Repo-internal references:

- [`docs/02-models.md`](./02-models.md) — model trade-offs, what didn't work, queued candidates.
- [`docs/03-serving.md`](./03-serving.md) — sampler defaults baked into the `*-serve` scripts.
- [`docs/04-tool-calling.md`](./04-tool-calling.md) — chat template fix for Qwen3-Coder, tool-call verification flow.
- [`docs/09-skills.md`](./09-skills.md) — skill format, locations, writing your own.
- [`docs/10-extensions.md`](./10-extensions.md) — extension format, what's wired into this repo.
