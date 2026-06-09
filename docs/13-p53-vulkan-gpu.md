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
The serve script now **defaults to instruct mode** (`THINK=off`): the `nemotron-nano-instruct.jinja`
template injects `detailed thinking off` into the system block and sampling is greedy (`--temp 0`).
Retest pending — if it's *still* a poor agent in instruct mode, the 8B ceiling is real and Qwen
wins; `THINK=on` restores reasoning mode.

## TODO

- [ ] Wire an instruct coder model (Qwen2.5/3-Coder) on the same Vulkan llama-server as the P53 pi default.
- [ ] Tune `CTX` / `--cache-type-k|v q8_0` for longest stable context on 8 GB.
- [ ] Revisit Nemotron-Nano-v2 (Mamba) once ollama/llama-server support stabilises.
- [ ] Optional: upgrade CUDA toolkit → 13.x for a native CUDA build (faster prefill than Vulkan).
