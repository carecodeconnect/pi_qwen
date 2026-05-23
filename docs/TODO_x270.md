# TODO — Linux / X270 ThinkPad port

Plan for adapting the Apple-Silicon-only baseline to a low-spec Linux laptop (ThinkPad X270 class). This is the second-class target documented in the README; the M1 Max path stays the reference.

## Target hardware

ThinkPad X270 (2017-era ultraportable), representative spec:

- Intel Core **i7-7600U** (Kaby Lake, 2c/4t, AVX2, no AVX-512)
- **14–16 GiB DDR4** (1 soldered + 1 SODIMM, 16 GiB max)
- Intel **HD 620** iGPU — no discrete GPU, no Metal, no CUDA
- Linux x86_64 (any modern distro)

## Why the baseline doesn't fit

Three blockers vs. the M1 Max reference in [`README.md`](../README.md) / [`02-models.md`](./02-models.md):

| Blocker | Effect on X270 |
|---|---|
| `-ngl 99` hard-wired in every `*-serve` | No Metal on Linux; on HD 620 the Vulkan backend gives only marginal speedup over pure CPU. Need `-ngl 0` (and an optional Vulkan path). |
| Smallest installable model is gpt-oss-20b at ~11 GiB resident | Fits 14 GiB numerically but leaves <3 GiB headroom — KV cache at 131k ctx OOMs. |
| 2 physical cores at ~2.8 GHz | Dense ≥7B drops below interactive threshold (~3–5 tok/s decode). Need 3–4B dense or small-active MoE. |

Kimi V2 / K2 family is ruled out — smallest variant is ~25 GiB Q4 (Kimi-Linear-48B-A3B), still won't load.

## Proposed candidates

All Q4_K_M GGUFs, all known to emit structured tool calls in current llama.cpp, ordered by recommended trial sequence:

| # | Model | Size | Expected decode (i7-7600U, CPU-only) | Notes |
|---|---|---|---|---|
| 1 | **Qwen3-1.7B** | ~1.1 GiB | (fastest TTFT of the set) | **Current X270 default.** Same base as jhana-rs (Phase 1 PASS, 2026-05-15). Replaced Qwen3-4B as default — 4B TTFT too slow for interactive pi loops on i7-7600U. |
| 2 | **Qwen2.5-Coder-3B-Instruct** | ~2 GiB | ~8–10 tok/s | Smallest viable coder; FAILs `tool-call-test` under `tool_choice: auto` — use for completion only. |
| 3 | **Qwen2.5-Coder-7B-Instruct** | ~4.5 GiB | ~3–5 tok/s | Quality jump; borderline interactive. |
| 4 | **Qwen3-4B-Instruct-2507** | ~2.5 GiB | ~3.3 tok/s decode | Previous X270 default. Solid tool-calling but TTFT too slow on i7-7600U. |
| 5 | gpt-oss-20b MXFP4 *(already wired)* | ~11 GiB | ~3–5 tok/s | MoE 3.6B active is CPU-tractable, but **OOM risk** — needs `-c 8192`, no other workload. |

Start with #1, validate the full pipeline (serve → `tool-call-test` → pi session), then expand.

## Work items

### 1. Install scripts

- [ ] `install/qwen-coder-3b.sh` — mirror [`install/gpt-oss-20b.sh`](../install/gpt-oss-20b.sh):
  - `HF_REPO=Qwen/Qwen2.5-Coder-3B-Instruct-GGUF`
  - `GGUF_NAME=qwen2.5-coder-3b-instruct-q4_k_m.gguf`
  - `MODEL_DIR=$HOME/models/qwen2.5-coder-3b`
  - Copy `scripts/qwen-coder-3b-serve` into `~/bin`.
- [ ] `install/qwen-coder-7b.sh` — same pattern, Q4_K_M.
- [ ] `install/base.sh` warning: `brew install llama.cpp` is macOS-only. Add a Linux branch suggesting `apt install llama.cpp` (Debian trixie+) or building from source. Detect with `uname -s`.

### 2. Serve scripts

- [ ] `scripts/qwen-coder-3b-serve` — mirror [`scripts/qwen-serve`](../scripts/qwen-serve), changes:
  - `MODEL` default points at the 3B GGUF
  - `-ngl 99` → `-ngl 0` (or `${NGL:-0}` so Vulkan users can override)
  - `-c 131072` → `${CTX:-16384}` — KV cache dominates RSS on small-weight models
  - Add `-t 4` (match logical cores)
  - Drop `-fa on` if it errors on CPU backend; verify with `llama-server --help`
  - Qwen2.5-Coder embeds a working tool-call template — confirm with `tool-call-test` before adding a `fetch-template` step.
- [ ] `scripts/qwen-coder-7b-serve` — same pattern.
- [ ] Document `NGL` env override in [`03-serving.md`](./03-serving.md) for users with Vulkan-capable iGPUs.

### 3. Config

- [ ] `config/models.json` — append two entries under the existing `local-llamacpp` provider:
  - `local-qwen2.5-coder-3b` (contextWindow 16384, reasoning false)
  - `local-qwen2.5-coder-7b` (contextWindow 16384, reasoning false)

### 4. Docs

- [ ] New `docs/12-linux-cpu.md` — sibling to `01-quickstart.md`, scoped to Linux + CPU:
  - Hardware floor (14 GiB RAM, AVX2, 4 logical cores)
  - llama.cpp install on Linux (apt / build-from-source / Vulkan optional)
  - Model choice (link to this TODO's candidate table)
  - Expected throughput numbers once measured
  - Known gaps vs. Apple Silicon path (no Metal flags, smaller context, smaller models)
- [ ] [`README.md`](../README.md) "Tested on" section — add a one-line pointer: *Linux/CPU path: see [docs/12-linux-cpu.md](docs/12-linux-cpu.md).*
- [ ] [`02-models.md`](./02-models.md) — add an "X270-class hardware" subsection under *Next model trials* listing the 3 candidates above with rationale.

### 5. Benchmarking

- [ ] Run [`bench/throughput.sh`](../bench/throughput.sh) on the X270 against models 1–3 once installed. Record:
  - pp512, pp2048, tg128, tg512
  - peak RSS (`/usr/bin/time -v`)
  - CPU temp under sustained load (X270 throttles aggressively)
- [ ] Append a second results table to `README.md` or [`05-benchmarking.md`](./05-benchmarking.md) so the M1 Max ↔ X270 gap is explicit.

### 6. Optional: Vulkan iGPU path

Only after the CPU baseline is proven:

- [ ] Build llama.cpp with `-DGGML_VULKAN=ON` against HD 620 (Mesa ANV/RADV not relevant — use Intel's ANV).
- [ ] Re-run benchmarks at `NGL=20` and `NGL=99` to see if partial offload helps.
- [ ] Document in `docs/12-linux-cpu.md` only if the speedup is ≥30% — otherwise leave it as a footnote.

## Acceptance criteria

Linux/X270 path is "done" when:

1. Fresh X270 with llama.cpp + pi + uv installed can run `install/qwen-coder-3b.sh` → `qwen-coder-3b-serve` → `tool-call-test` → `pi --model local-qwen2.5-coder-3b` end-to-end.
2. `tool-call-test` passes — structured `tool_calls` fire.
3. Decode ≥ 6 tok/s on the 3B model (interactive threshold).
4. `docs/12-linux-cpu.md` is enough for a stranger to reproduce without reading the macOS docs.

## Non-goals

- Porting GLM-4.5-Air, Qwen3-Coder-30B, Qwen3-Coder-Next-80B, or any Kimi-family model to the X270 — they don't fit.
- Supporting CUDA / ROCm — out of scope for this hardware tier.
- Making the X270 path the default. M1 Max stays the reference; this is a documented secondary target.
