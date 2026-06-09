# P53 / Vulkan GPU — Nemotron-Nano for pi

Third hardware target for this sandbox, alongside the Apple-Silicon default (Metal,
[docs/02-models.md](./02-models.md)) and the ThinkPad X270 (CPU, [docs/12-linux-cpu.md](./12-linux-cpu.md)).

## Hardware

| | |
|---|---|
| Machine | ThinkPad P53 (`honeyball`), Ubuntu 26.04 |
| GPU | **NVIDIA Quadro RTX 4000 Mobile** — Turing (TU104), **compute 7.5**, **8 GB VRAM** |
| iGPU | Intel UHD 630 (Vulkan device 0 — *not* used; Quadro is device 1) |
| Driver | 595.x (CUDA 13.2 runtime capable) |

8 GB VRAM is the binding constraint, and compute 7.5 has no native FP8/MXFP4 — so plain
**GGUF Q4/Q5** is the path (no gpt-oss-style MXFP4 acceleration).

## Why Vulkan, not CUDA

We wanted `local-llamacpp` with CUDA (matches the repo), but the host toolchain blocks it:

1. **No prebuilt CUDA-Linux llama.cpp.** ggml-org releases ship Linux binaries for CPU,
   **Vulkan**, ROCm and OpenVINO only — CUDA prebuilts are Windows-only. CUDA on Linux
   means building from source.
2. **The CUDA toolkit can't build here.** Installed toolkit is **12.3**; Ubuntu 26.04 ships
   gcc 12–15 and a very new glibc. `nvcc` rejects gcc > 12 (`unsupported GNU version`), and
   even with gcc-12 the CUDA 12.3 headers conflict with the new glibc
   (`cospi … exception specification incompatible`). CUDA-from-source would need a CUDA
   **toolkit upgrade** (~13.x, matching the driver) — a heavyweight, deferred change.
3. **Rust engines don't dodge it.** mistral.rs / candle are CUDA-or-Metal (no Vulkan) and
   compile CUDA kernels via the same toolkit; no win.

**Vulkan sidesteps all of it.** The prebuilt `llama-b<tag>-bin-ubuntu-vulkan-x64` runs on
the Quadro with **no CUDA toolchain**, and it is the same `llama-server` — so pi's
`local-llamacpp` provider (`:8080`, OpenAI API, `--jinja` tool calls) is unchanged. (ollama
also works because it bundles its own `libcudart`; we keep llama-server for repo
consistency, jinja templates, and flag control.)

## Models

Llama-3.1-based Nemotron-Nano (so they convert to GGUF cleanly and tool-call under the
Llama-3.1 template). The **v2 (9B/12B) hybrid Mamba (`nemotron_h`) models are excluded** —
llama.cpp support is new and ollama/llama-server handling was still buggy at writing.

| Alias (`-a` / model `id`) | Model | Q4 size | VRAM loaded | Notes |
|---|---|---|---|---|
| `nemotron-nano-8b` | Llama-3.1-Nemotron-Nano-8B-v1 | ~4.9 GB | ~6.6 GB (measured) | best quality that fits 8 GB; keep ctx modest |
| `nemotron-nano-4b` | Llama-3.1-Nemotron-Nano-4B-v1.1 | ~2.8 GB | ~3.5 GB | more KV/context headroom |

Both are **reasoning** models (`reasoning: true`) — they emit `<think>`. Suppress for agent
loops with a system message **`detailed thinking off`** (the test script and pi prompts do this).

`nemotron-mini` (4B) was rejected: not Llama-arch (NVIDIA `<extra_id_0>` format), tool-call
output unparseable by the OpenAI server layer, and only 4K context.

## Setup → serve → test

```bash
# 1. install: prebuilt Vulkan llama.cpp + both GGUFs (idempotent, resumable)
./install/nemotron-vulkan.sh

# 2. serve (leave running; logs to /tmp/nemotron-serve.log)
./scripts/nemotron-vulkan-serve                       # 8B, Quadro, :8080
# 4B instead:
MODEL=$HOME/models/nemotron-nano-4b-Q4_K_M.gguf ALIAS=nemotron-nano-4b ./scripts/nemotron-vulkan-serve

# 3. test (another terminal) — tool-call gate + VRAM/speed, logs to /tmp/nemotron-test.log
ALIAS=nemotron-nano-8b ./scripts/nemotron-vulkan-test
```

The Quadro is selected via `GGML_VK_VISIBLE_DEVICES=1` (device 0 is the Intel iGPU). Confirm
GPU offload with the test's `nvidia-smi` block (several GB used on the Quadro) and the serve
log's device/offload lines.

## pi wiring

The serve script binds `:8080`, so the existing **`local-llamacpp`** provider already points
at it — `config/models.json` adds `nemotron-nano-8b` and `nemotron-nano-4b` there. Run with:

```bash
pi --model nemotron-nano-8b      # or nemotron-nano-4b
```

## Results (measured — `nemotron-nano-8b`, ctx 16384, P53 Quadro/Vulkan)

- **Tool calls: PASS** — clean structured `tool_calls` (`get_weather({"city":"Paris"})`).
- **Chat template (important):** the GGUF-embedded Nemotron template passes the *single-turn*
  weather test, but **breaks pi's multi-turn agent loop** — it `raise_exception`s
  *"Conversation roles must alternate between user/tool and assistant"* on the non-alternating
  sequences pi produces (tool results + context compaction), and llama-server can't auto-build a
  tool parser from it. Fix: serve with llama.cpp's **`meta-llama-Llama-3.1-8B-Instruct.jinja`**
  (role-lenient, tool-parser-tested; Nano is Llama-3.1-derived) via `--chat-template-file` —
  now the serve-script default (`CHAT_TEMPLATE`), fetched by the install script.
- **VRAM: 6595 MiB / 8192** with all layers offloaded (`-ngl 99`) — ~1.6 GB headroom.
- **Decode: ~29–45 tok/s** (usable for agent loops).
- **Prefill: ~6–10 tok/s** — slow; Vulkan-on-Turing weakness, not present on CUDA/Metal.
  Mitigations: keep prompts/skills lean, lean on the prompt cache (enabled), or upgrade to CUDA.
- **Quirk (embedded template only):** the embedded template also leaked an empty `<TOOLCALL>[]`
  marker into tool-less replies — another reason the Llama-3.1 template above is the default.

## Agent verdict — stack works, Nemotron-Nano is a poor pi agent

Ran pi end-to-end against `nemotron-nano-8b`. The mechanics are perfect (tools fire, no
errors, GPU ~44 tok/s decode), but the **model is an erratic agent**, in both directions:

- **Over-tools trivial prompts:** "hello?" → web-searched *and* code-searched "hello", then
  emitted a degenerate `code_search` with an **empty query**.
- **Under-tools real tasks:** "summarise this codebase" → used **no tools at all** and returned
  a canned *"I don't have access to the code"* non-answer (it didn't realise it could read files).
- **Burns context** fast (repeated auto-compaction on trivial turns).

This matches [docs/12-linux-cpu.md](./12-linux-cpu.md): the X270 deliberately chose an *instruct*
model (Qwen3-4B-Instruct-2507) over a *reasoning* one for pi loops, because reasoning models
over-think and stall. **Nemotron-Nano (reasoning) is the same failure mode.** A system-prompt
nudge ("only call tools when needed; never empty args; answer greetings directly") helps but
doesn't fix the judgment.

**Recommendation: make an *instruct coder* model (Qwen2.5/3-Coder, 7B-class) the P53 pi default;**
keep Nemotron-Nano documented here as "validated mechanically, but a weak agent — not the default."

**Caveat before writing it off — we tested the wrong mode.** Nemotron-Nano is one checkpoint with
a runtime toggle: `detailed thinking off` switches it to *non-reasoning / instruct* mode (NVIDIA
recommends **greedy** decoding for it). The runs above used reasoning-mode sampling (`--temp 0.6`)
and pi never sent the directive — i.e. it ran in *reasoning* mode, the worst case for an agent.
The serve script defaults to instruct mode (`THINK=off`): greedy + forced `detailed thinking off`.

**Instruct-mode retest result: still not an agent — and it's partly upstream.** In `pi`, instruct
mode stopped the over-thinking but the model **hallucinated its own tool list as the "codebase
summary," made no real tool calls**, and even when told "use tools, do not guess" returned a
manual-git essay ("I don't have access"). When it *did* attempt a call, llama.cpp threw
`Failed to parse input at pos 47` (it emitted the param *schema* shape, not arguments).

A GitHub search shows this is **not just the model** — llama.cpp's **Llama-3.x-Nemotron tool
parser is unmerged** (PR #15083), the `Failed to parse input … tool calling` 500 is a **known open
bug** (#20650), and the generic autoparser is documented to misclassify Nemotron output
(#20325, #20754). So Nemotron-Nano tool-calling on the current llama.cpp release is **upstream-
incomplete**, not a config we can fully fix.

Workaround attempted: serve now defaults to Nemotron's **own** template (native
`<AVAILABLE_TOOLS>`/`<TOOLCALL>` format), patched to drop the role-alternation raise and force
instruct mode (`nemotron-native-instruct.jinja`). This **partially worked** — with the native
template the model made a *real* tool call (`ls` executed and returned the actual repo contents:
`install`, `pyproject.toml`, `scripts`, `src`, `uv.lock`). **But the next call mangled:** a
**well-formed** `{"name":"bash","arguments":{"command":"ls …/config"}}` died with
`Failed to parse input at pos 495`. llama.cpp failed to parse *valid* tool-call JSON — i.e. the
blocker is demonstrably the **parser**, not the model. Intermittent success, but unreliable for a
sustained agent loop; capped by the missing parser. **Net: use an instruct coder (Qwen2.5-Coder, first-class llama.cpp tool support)
as the P53 pi default; keep Nemotron-Nano here as "mechanically validated, but tool-calling is
upstream-blocked — revisit when PR #15083 lands."**

### Upstream references (llama.cpp tool-calling for Llama-3.x / Nemotron)

The agentic failures above are tracked upstream — this is why we're **parking the Nemotron
agent test rather than chasing more config**:

- **[ggml-org/llama.cpp#15083](https://github.com/ggml-org/llama.cpp/pull/15083)** — *PR (open):*
  "model: add reasoning/tool parsing to Llama 3.x Nemotron." The actual parser we need; **not yet
  merged**, so current releases have no first-class Llama-3.x-Nemotron tool parsing.
- **[ggml-org/llama.cpp#20650](https://github.com/ggml-org/llama.cpp/issues/20650)** — *Issue
  (open):* "500 — Failed to parse input at pos x when tool calling." **Our exact error.**
- **[ggml-org/llama.cpp#20325](https://github.com/ggml-org/llama.cpp/issues/20325)** /
  **[#20754](https://github.com/ggml-org/llama.cpp/issues/20754)** — autoparser misplaces /
  misclassifies Nemotron-Nano output (non-thinking content read as reasoning).
- **[ggml-org/llama.cpp#24081](https://github.com/ggml-org/llama.cpp/issues/24081)** — Nemotron
  Nano v2: `json_schema` + greedy → 500 "Failed to parse input … `<SPECIAL_12>`."
- **[ggml-org/llama.cpp#23029](https://github.com/ggml-org/llama.cpp/pull/23029)** — *PR (open):*
  "chat: add Nemotron Nano v2 specialized parser" (the Mamba-hybrid line; also unmerged).
- **[ggml-org/llama.cpp#20268](https://github.com/ggml-org/llama.cpp/issues/20268)** /
  **[#22043](https://github.com/ggml-org/llama.cpp/issues/22043)** — Nemotron-Nano-9B-v2 broken on
  llama-server; `parallel_tool_calls` infinite loop on Nemotron-3-Nano-4B.

### Test status: CONCLUDED (parked) — 2026-06-09

We exhausted the configurable surface: reasoning vs **instruct** mode (`detailed thinking off` +
greedy), the **lenient Llama-3.1** template, and Nemotron's **own native** `<TOOLCALL>` template
(role-raise patched out). Tool-calling remained unreliable, and the root cause is an **unmerged
upstream parser (#15083)**, not our setup — so there is nothing further to tune locally. Decision:
**Nemotron-Nano is not the P53 pi agent; Qwen2.5-Coder-7B-Instruct is.** Re-open this test when
#15083 merges and we bump the `llama.cpp` build (`LLAMA_TAG` in `install/nemotron-vulkan.sh`).

## The real blocker: llama-server tool-call PARSING (use ollama for small models)

Testing Qwen2.5-Coder-7B exposed that the "hallucination" of *both* models was **never a model
ceiling — it's llama-server's tool-call parser** on this build (b9581, Vulkan):

- Qwen2.5-Coder emits `<function name="list_dir" arguments='{"path":"."}'/>`; llama-server's
  `peg-native` autoparser **does not convert it to `tool_calls`**, so pi sees raw text and the model
  *appears* to hallucinate running commands (it prints `$ bash ls` markdown with invented output).
  This is the exact failure described in [docs/04-tool-calling.md](./04-tool-calling.md), but the
  official-vs-bundled Qwen2.5 template swap **does not fix it** (both templates are identical and
  both yield the unparsed `<function>` form).
- Nemotron-Nano hits the same wall via a different format (`<TOOLCALL>` + upstream parser gap #15083).

**ollama parses both cleanly** — it bundles the correct per-model tool template + parser. Verified
via its OpenAI endpoint: `qwen2.5-coder` returns a clean structured `tool_call`
(`list_dir({"path":"."})`, no `<function>` tag) and handles multi-turn tool results.

**Resolution:** added a **`local-ollama`** provider (`http://127.0.0.1:11434/v1`) to
`config/models.json` with `qwen2.5-coder`. One-shot setup (installs ollama, pulls the model,
deploys the provider config):

```bash
./install/qwen-ollama.sh
pi --model qwen2.5-coder          # ollama — tool calls actually parse
```

The `local-llamacpp` Vulkan path stays for non-tool use / benchmarking, but for **agentic pi on the
P53, use the ollama provider** until llama.cpp's small-model tool parsing improves (track #15083 and
the Qwen `<function>` parsing). This is a llama.cpp-version issue, not the GPU/Vulkan stack.

**VALIDATED in pi (2026-06-09):** `pi --model qwen2.5-coder` (ollama) executed a real
`read README.md` and produced an **accurate, grounded** summary of the actual repo (correct model
lineup, serve scripts, docs paths) — no invention. **This is the P53 pi default.**

Residual 7B-class quirks (usable, not flawless):
- **Over-tools trivial prompts** (read docs for "hello?"). Curb with a system-prompt nudge:
  "only call tools when the task needs them; answer greetings directly."
- **Intermittent prior-vs-tool grounding lapse:** `$ date` returned the correct `…Jun 2026`, but
  once the model answered "June 5, 2023" from its training prior; on pushback ("you got it wrong")
  it re-read the tool output and corrected to "June 9, 2026." A nudge helps:
  "treat tool output as ground truth; never answer from training memory when a tool returned data."
- These are 7B-on-8 GB limits — a larger model would be steadier but doesn't fit the Quadro.

## TODO

- [x] Wire an instruct coder (Qwen2.5-Coder-7B-Instruct) — done (Vulkan serve + ollama provider).
- [x] A/B Qwen vs Nemotron in pi — done. **Winner: `qwen2.5-coder` via the ollama provider**
      (real tool calls, grounded summaries). Set as the P53 pi default.
- [ ] Add a system-prompt nudge to curb over-tooling of trivial prompts (greetings → answer directly).
- [ ] Re-test the llama-server (Vulkan) tool path after llama.cpp#15083 / Qwen `<function>` parsing
      lands (bump `LLAMA_TAG`) — would let us drop the ollama dependency for repo consistency.
- [ ] Tune `CTX` / `--cache-type-k|v q8_0` for longest stable context on 8 GB.
- [ ] Optional: upgrade CUDA toolkit → 13.x for a native CUDA build (faster prefill than Vulkan).
