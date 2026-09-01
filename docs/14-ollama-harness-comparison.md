# Ollama on the M1 Max — pi vs Claude Code, and which model to run

Fourth hardware/runtime record for this sandbox, alongside the Metal/llama.cpp default
([docs/02-models.md](./02-models.md)), the X270 ([docs/12-linux-cpu.md](./12-linux-cpu.md)) and the
P53 ([docs/13-p53-vulkan-gpu.md](./13-p53-vulkan-gpu.md)).

Prompted by a work agent-runner gaining Ollama support, which points Claude Code at Ollama's own
Anthropic-compatible endpoint. The
question was which local model to use. The answer turned out to be less interesting than the
discovery that **the harness matters more than the model**.

## Bottom line

- **Run local models through pi, not Claude Code.** Same model, same Ollama server, same task: pi is
  3–25× faster and marginally more reliable. Claude Code ships its full tool schemas and instructions
  on every call; on a local model that prefill *is* the runtime.
- **`gpt-oss:20b` is the pick on this box** — the only model that passed every run in both harnesses,
  and the fastest to a correct answer on the real task.
- **A synthetic gate is not enough.** `qwen3-coder:30b` won on FizzBuzz and then failed the real task
  by emitting its tool call as unparsed XML — the same Qwen3-Coder format problem recorded against
  the higgs path in [docs/07-engines.md](./07-engines.md), now seen on the Ollama path too.

## Hardware and runtime

| | |
|---|---|
| Machine | MacBookPro18,2 — Apple M1 Max, 64 GB, macOS 26.5.2 |
| Ollama | 0.33.2 (serves a native Anthropic API on `:11434`, no LiteLLM shim needed) |
| pi | 0.80.2, via the `local-ollama` provider (`openai-completions`, `:11434/v1`) |
| Claude Code | `ANTHROPIC_BASE_URL=http://localhost:11434`, `ANTHROPIC_AUTH_TOKEN=ollama` |

## The agent gate — every model, both harnesses

Task: *create `fizzbuzz.py` for 1..15, then actually run it with python3*. Pass = the file exists and
executes. Two trials each, grouped by model so each loads into memory once.

| Model | Size | pi | Claude Code |
|---|---|---|---|
| `gpt-oss:20b` | 14 GB | **2/2** — 37s, 8s | **2/2** — 139s, 86s |
| `qwen3-coder:30b` | 18 GB | **2/2** — 14s, 10s | 1/2 — 260s, no-file |
| `qwen3:30b-a3b` | 18 GB | **2/2** — 49s, 36s | **2/2** — 245s, 263s |
| `qwen3:8b` | 5.2 GB | **2/2** — 46s, 53s | 1/2 — **timeout 422s**, 348s |
| `gemma4` | 9.6 GB | 1/2 — 42s, no-file | **2/2** — 99s, 94s |

pi 9/10, Claude Code 8/10 — but the times are the story. Ollama's log puts a pi turn at
`n_past = 781` tokens; a bare two-token prompt round-trips in 1s, so Claude Code's 86–422s is
overwhelmingly system-prompt prefill, paid again on every invocation.

## The real task — reporting what a tool returned

FizzBuzz only proves a model can call a tool. This asks whether it reports what came back: run a
real internal script that queries a live database and state the three figures it prints. The
expected values were verified independently by running the script directly. They are live
production numbers, so they cannot be answered from training priors — the model either ran the
tool or it did not.

| Model | Time | Result |
|---|---|---|
| `gpt-oss:20b` | 15s | **correct** — all three figures matched |
| `qwen3:30b-a3b` | 41s | **correct** — all three figures matched |
| `qwen3-coder:30b` | 18s | **failed** — tool never ran |

`qwen3-coder:30b` emitted the call as literal text instead of a structured tool call:

```
<function=bash><parameter=command>bash path/to/the/script.sh --env prod</parameter></function>
```

This is the XML-vs-JSON tool-call split from [docs/07-engines.md](./07-engines.md): Qwen3-Coder
follows Qwen's official template and emits XML, and a harness whose parser expects JSON sees only
text. It is intermittent rather than total — the same model passed the FizzBuzz gate 2/2 — which
makes it worse for unattended runs, not better.

**Lesson, matching [docs/12-linux-cpu.md](./12-linux-cpu.md): "real-pi tool use matters more than
`tool-call-test`."** A model can pass a synthetic gate and still be unusable on real work.

## `OLLAMA_CTX_SIZE` does not do what it looks like it does

`launch-agent.sh` exports `OLLAMA_CTX_SIZE=65536`, but the server ignores it — `ollama ps` reported
`CONTEXT 262144` and the log `n_ctx = 262144`, the model's full 256K default. On a 64 GB machine that
is **45 GB resident for one model**, leaving 19 GB for everything else.

Context has to be pinned **on the model**, via a Modelfile:

```
FROM qwen3-coder:30b
PARAMETER num_ctx 65536
```

`ollama create qwen3-coder-64k -f …` reuses the existing blobs, so it costs no extra disk. Measured:

| | resident | context | gate |
|---|---|---|---|
| `qwen3-coder:30b` (default) | **45 GB** | 262144 | PASS 22s |
| `qwen3-coder-64k` (pinned) | **25 GB** | 65536 | PASS 11s |

**20 GB reclaimed**, and faster, for a context window larger than either harness uses.

Second, unrelated gap: Claude Code warns it does not recognise Ollama model names and assumes a
200k window, so it auto-compacts at the wrong boundary. Set
`CLAUDE_CODE_MAX_CONTEXT_TOKENS` to the real window alongside `num_ctx`.

## Models ruled out before download

- **`ornith-1.5:9b`** — Ollama lists `vision` only, **no `tools`**. Cannot drive an agent loop at any
  size. (The older `ornith:9b` does have tools.) Same class as the DeepSeek-Coder-V2-Lite result in
  [docs/02-models.md](./02-models.md): architecturally appealing, does not speak tool calling.
- **`qwen3.8-flash-next`** — 125B total / 6B active plus 51B N-gram embeddings; smallest Ollama tag
  is 105 GB against 64 GB of RAM. Strong agentic-coding scores (SWE-bench Pro 62.5) and QwenCloud
  serves it over an Anthropic-compatible endpoint, so it drops into the same wiring — but as a cloud
  model, not a local one.
- **GLM-4.5-Air** — worked here but at ~20 tok/s (2.5× slower than Qwen-30B); its GGUF has been
  removed from this machine and its entries dropped from `config/models.json`.
