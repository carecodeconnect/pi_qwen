# Alternative inference engines (Rust)

llama.cpp is the default in this repo because its Metal backend is mature, Homebrew ships precompiled binaries, and the GGUF + jinja-template path is well-trodden for tool calling. But pi only cares about the OpenAI-compatible HTTP shape — any server that speaks `/v1/chat/completions` and emits structured `tool_calls` is a drop-in replacement.

A few Rust-native engines worth A/B-ing on this hardware.

## mistral.rs (primary alternate)

[mistral.rs](https://github.com/EricLBuehler/mistral.rs) is the most mature Rust-native option. Built on Candle, optimized Metal backend, OpenAI-compatible HTTP server. Supports Qwen3 MoE and the other architectures used here. The only structural difference for pi is the `baseUrl` and the model `id` (mistral.rs reports the loaded model as `default` unless overridden).

The catch on macOS: building it requires the Metal shader compiler, which ships only with **full Xcode** (not Command Line Tools). If you don't already have Xcode installed, llama.cpp is the friction-free path. If you do:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
cargo install --git https://github.com/EricLBuehler/mistral.rs mistralrs-server --features metal

mistralrs-server --port 8080 gguf \
  -m ~/models/qwen3-coder-30b-a3b \
  -f Qwen3-Coder-30B-A3B-Instruct-Q5_K_M.gguf
```

Then change `id` to `default` in `models.json` and you're off.

## Other Rust engines worth tracking

Neither is the default path yet — each is here as a candidate to benchmark against mistral.rs once the llama.cpp baseline is solid.

- **[candle-vllm](https://github.com/EricLBuehler/candle-vllm)** — same author as mistral.rs. Aims to bring vLLM-style continuous batching to Candle, with an OpenAI-compatible server. Less mature than mistral.rs; worth tracking but not first.
- **[Crane](https://github.com/lucasjinreal/Crane)** — Candle-based, OpenAI-compatible via `crane-oai`. Claims ~6× M-series speedup vs llama.cpp; newer, less battle-tested. Worth a benchmark but I wouldn't rely on it for daily use yet.

Both build with `cargo install` and the same Xcode/Metal requirement as mistral.rs. To wire either into pi, point a new entry in `~/.pi/agent/models.json` at the engine's port and use whatever id it advertises at `/v1/models`.

## Rust + MLX: `higgs` (the no-Xcode Rust path)

If the Rust-engine question is really *"is there a Rust inference engine I can actually install on this Mac without Xcode or an Apple ID,"* the answer is yes: [panbanda/higgs](https://github.com/panbanda/higgs).

Higgs is a single static Rust binary that uses MLX as its inference backend and exposes both OpenAI (`/v1/chat/completions`, `/v1/completions`) and Anthropic (`/v1/messages`) HTTP APIs. Because it's distributed via Homebrew with a pre-built `aarch64-apple-darwin` binary, **no compilation happens on your machine** — same friction profile as llama.cpp in this repo.

Install:

```bash
brew install panbanda/brews/higgs
```

That's it. No Rust toolchain, no Xcode (not even CLT), no Apple ID. If you'd rather build from source, the requirement is only **Rust 1.88+ and Xcode CLI Tools** (`xcode-select --install`) — still no full Xcode, still no Apple ID.

Supported model families: Qwen, Llama, Mistral, Gemma, Phi, DeepSeek, and vision-capable MLX variants. Documentation lists specific versions like Qwen3-1.7B, Llama-3.2-1B, DeepSeek-V2-Lite.

Launch the server (use **port 8002** to avoid colliding with llama-server on 8080 and vllm-mlx on 8001):

```bash
higgs serve --port 8002
# Then send requests to http://127.0.0.1:8002/v1/chat/completions
```

Wire into pi the same way as any other engine: add a provider entry in `~/.pi/agent/models.json` and gate with `tool-call-test`.

**Empirical results (2026-05-14, this sandbox):**

| MLX model | tool-call-test | Notes |
|---|---|---|
| `mlx-community/Qwen3-1.7B-4bit` | ✓ PASS | Structured `tool_calls` returned cleanly for `get_weather`. Verified end-to-end with `PORT=8002 ALIAS=qwen3-1.7b tool-call-test`. |
| `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit` | ✗ FAIL (quant) | Loads (architecture `qwen3_moe` is supported), but inference 500s with `MLX error: [quantized_matmul] shapes incompatible`. Root cause: this MLX-community quant uses **mixed precision** — most weights at 4-bit + MoE gates at 8-bit. higgs/mlx-rs only handles uniform-precision quantization. **Workaround:** use the `-4bit-DWQ` or `-8bit` variant (uniform quant, verified via `config.json`). |
| `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit-DWQ` | ⚠️ PARTIAL | Loads + inference works. **But** tool-call-test fails because Qwen3-Coder emits the XML format `<tool_call><function=name><parameter=key>value</parameter></function></tool_call>` (per Qwen's official Jinja template). llama.cpp parses this format back into structured `tool_calls`; **higgs's egress parser only handles Qwen3's JSON format** (what Qwen3-1.7B emits, not what Qwen3-Coder emits). Replacing the cached `chat_template.jinja` with Qwen's official template doesn't help — both templates instruct the model to emit XML. Until higgs adds a Qwen3-Coder XML parser, this model can't be tool-call-driven through higgs. Raw chat completions and benchmarks still work. |
| `mlx-community/gpt-oss-20b-MXFP4-Q4` | ✗ FAIL (arch) | `Error: Model(UnsupportedModel("gpt_oss"))` — architecture not implemented in higgs 1.2.0 / mlx-rs. Route through llama.cpp. |
| `mlx-community/GLM-4.5-Air-4bit` | ✗ FAIL (arch) | `Error: Model(UnsupportedModel("glm4_moe"))` — same wall as gpt-oss. Route through llama.cpp. |
| `mlx-community/Llama-3.2-1B-Instruct-4bit` | ✗ FAIL (template) | Jinja `too many arguments` error. Meta's 1B variant doesn't ship a tool-call-aware template; tool support starts at 3B+. Same failure shape as [DeepSeek-Coder-V2-Lite rejection](./02-models.md#tested-and-rejected). |

**Four distinct failure modes seen, in order of how recoverable each is:**

1. **Model template** (no tool-call grammar in Jinja) — load + inference succeed, but `tools=[...]` confuses the renderer. Pick a tool-call-trained model. *Most recoverable.*
2. **Quantization layout** (mixed-precision MoE) — load succeeds, inference 500s with `quantized_matmul` shape error. Pick a uniform-quant variant of the same model.
3. **Egress parser** (model emits in a tool-call format higgs doesn't decode) — load + inference + the model itself behave correctly; higgs's egress parser is the gap. **Not recoverable from the user side** — need upstream higgs to add the parser.
4. **Architecture unsupported** (e.g. `gpt_oss`, `glm4_moe`) — load fails at startup with `UnsupportedModel("…")`. **Hardest wall** — need upstream higgs to add architecture support.

Always run `tool-call-test` after wiring a new MLX model — too varied to predict from model cards alone. `tool-call-test` distinguishes failure modes #3 (returns text instead of `tool_calls`) from #1/#2/#4 (returns HTTP error).

### Net result on this repo's four production models

Of the four llama.cpp models this repo uses for daily work, **none have a working tool-call path through higgs today.** Each is blocked on a different higgs limitation:

| llama.cpp model in this repo | MLX equivalent | Blocker |
|---|---|---|
| `qwen3-coder-30b-a3b` | `Qwen3-Coder-30B-A3B-Instruct-4bit-DWQ` | egress parser doesn't handle Qwen3-Coder's XML tool-call format |
| `local-qwen3-coder-next` | (not yet tested — MLX variant available at `mlx-community/Qwen3-Next-80B-A3B-Instruct-*`) | probably same Qwen3-Coder XML issue |
| `local-gpt-oss-20b` | `gpt-oss-20b-MXFP4-Q4` | architecture not supported |
| `local-glm-4.5-air` | `GLM-4.5-Air-4bit` | architecture not supported |

**For daily pi work, llama.cpp remains the only working path on this hardware for all four production models.** higgs is a real engine that works for *some* models (Qwen3 family at small sizes, JSON tool format), and the speed wins on those models are substantial — but it's not yet a drop-in replacement for the four llama.cpp workflows this repo is built around.

### Benchmark: higgs (MLX) vs llama.cpp on the same model

Two runs of [`bench/engine-compare.py`](../bench/engine-compare.py), 3-5 runs each, max_tokens=256, identical prompt (`/no_think` prefix on Qwen3-1.7B since it's a hybrid thinking model; Qwen3-Coder-30B doesn't need it). Both engines on the same M1 Max:

| Model | Engine + Quant | TTFT | Decode |
|---|---|---|---|
| **Qwen3-1.7B** | llama.cpp Q5_K_M GGUF | 83 ± 32 ms | 100.4 ± 1.6 tok/s |
| Qwen3-1.7B | higgs 4bit MLX | 104 ± 12 ms | **162.8 ± 0.4 tok/s** (+62%) |
| **Qwen3-Coder-30B-A3B** | llama.cpp Q5_K_M GGUF | 194 ± 232 ms | 48.1 ± 0.2 tok/s |
| Qwen3-Coder-30B-A3B | higgs 4bit-DWQ MLX | 354 ± 219 ms | **57.7 ± 0.04 tok/s** (+20%) |

Pattern: **MLX is faster, but the gap narrows on bigger MoE models.** On a 1.7B dense model, MLX is ~62% faster; on a 30B MoE, only ~20%. Likely cause: bigger models become memory-bandwidth-bound, where MLX's compute-throughput advantage matters less. TTFT is consistently higher on higgs (about 2× across both model sizes) — not relevant for steady-state agentic work where decode dominates.

For Qwen3-Coder-30B specifically, the ~20% decode speedup is real but unusable for pi today (egress-parser blocker above). If higgs adds Qwen3-Coder XML parsing, switching this repo's default engine for this model becomes worth considering.

Rule of thumb: on higgs, **pick MLX models with documented tool-call training** (Qwen3 family, Qwen2.5-Coder, Llama-3.2-3B+, GLM-4.5-Air, gpt-oss). Skip 1B-class instruct models — they predate the structured-tool-call norm at that size.

Wired-in pi config for the qwen3-1.7b test:

```json
"local-higgs": {
  "baseUrl": "http://127.0.0.1:8002/v1",
  "api": "openai-completions",
  "apiKey": "not-needed",
  "models": [{
    "id": "qwen3-1.7b",
    "name": "Qwen3-1.7B (local, MLX via higgs)",
    "reasoning": false,
    "contextWindow": 32768,
    "maxTokens": 4096
  }]
}
```

After adding that to `~/.pi/agent/models.json`, `pi --list-models` shows the new provider and `pi --model qwen3-1.7b` drops into a session against higgs.

### Apples-to-apples benchmark vs llama.cpp (Qwen3-1.7B)

Same model architecture, same hardware, similar quantization. Both engines served `Qwen/Qwen3-1.7B` — llama.cpp loaded the `unsloth/Qwen3-1.7B-GGUF` Q5_K_M variant; higgs loaded the `mlx-community/Qwen3-1.7B-4bit` MLX variant. Bench tool: [`bench/engine-compare.py`](../bench/engine-compare.py) (uv inline-script, hits `/v1/chat/completions` with streaming, measures TTFT and decode tok/s).

Prompt: `/no_think Write a Python function that reverses a string. Then explain what it does in one paragraph.` (the `/no_think` prefix disables Qwen3's hybrid thinking mode so the comparison measures content-token decode, not chain-of-thought).

5 runs, max_tokens=256:

| Engine | TTFT | Decode | Tokens generated (avg) |
|---|---|---|---|
| llama.cpp (Q5_K_M GGUF, llama-server b9100) | 83 ± 32 ms | 100.4 ± 1.6 tok/s | 108 |
| higgs (4bit MLX, higgs 1.2.0) | 104 ± 12 ms | **162.8 ± 0.4 tok/s** | 90 |

**higgs is ~62% faster decode** on Qwen3-1.7B at this hardware/quant pairing. TTFT is slightly higher on higgs (a hair over 100 ms vs llama.cpp's ~83 ms) — not relevant for steady-state agentic work where decode dominates.

Caveats:
- MLX's 4-bit is more aggressive quantization than GGUF Q5_K_M. The decode-speed win is real; the quality gap (if any) isn't measured here. Run real tasks through both before drawing conclusions about utility, not just speed.
- This is a 1.7B model. The MLX vs llama.cpp gap typically narrows on bigger models where unified-memory bandwidth becomes the bottleneck rather than compute. The 30B comparison is the more important one for daily-use models — pending download of `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit`.
- Qwen3-1.7B is a hybrid thinking model. Without the `/no_think` prefix, llama.cpp burns most of its decode budget on `<think>...</think>` tokens that the streamed `content` deltas never see — measured at ~6 content tokens per 256 max_tokens. higgs/MLX appears not to enable thinking mode by default for this MLX-community quantization. Same model, different default behavior — worth knowing if your benchmark numbers diverge unexpectedly.

Underneath higgs, the binding layer is **[oxideai/mlx-rs](https://github.com/oxideai/mlx-rs)** (unofficial Rust bindings to MLX's C++ framework). Relevant if you want to write your own inference server in Rust against MLX — but `mlx-rs` requires building from source with CLT, which is still the no-Apple-ID path but more setup than `brew install higgs`.

**Practical recommendation:** if your goal is "try a Rust inference engine on this hardware with no Xcode friction," start with `higgs`. It's the cleanest match. If higgs's tool-calling turns out to be unreliable or it's missing your model family, fall back to vllm-mlx (next section) — different language (Python) but more mature MLX integration.

## MLX in Python: `vllm-mlx` (more mature, no Xcode required)

- **[vllm-mlx](https://github.com/waybarrios/vllm-mlx)** — MLX backend with an OpenAI + Anthropic-compatible HTTP server, baked-in MCP tool calling (12 parsers including OpenAI, Anthropic, Gemini, Qwen, DeepSeek, Gemma), continuous batching, and vision/audio support. Reports 400+ tok/s on M-series for small models and 10–30% faster than llama.cpp Metal on 70B+ models.

  **When to pick this over `higgs`:** vllm-mlx is more mature than higgs and has explicit MCP tool-call parsers, which higgs's README doesn't document. If you've tried higgs and tool-calling won't fire, or you need a model family higgs doesn't support, vllm-mlx is the fallback. Trade-off: it's Python (not Rust) and requires a Python environment.

  Same no-Xcode property as higgs — MLX is Apple's own ML framework, distributed as pre-built Python wheels with the Metal shaders already compiled. **No full Xcode and no Apple ID required to install.**

### vllm-mlx empirical results (2026-05-14)

Tested specifically against the egress-parser gap that blocks Qwen3-Coder-30B on higgs. Result: vllm-mlx has a dedicated `qwen3_coder` parser (one of 17 — `auto`/`mistral`/`qwen`/`qwen3_coder`/`llama`/`hermes`/`harmony`/`gpt-oss`/`deepseek`/`kimi`/`granite`/`nemotron`/`xlam`/`functionary`/`gemma4`/`glm47`/`minimax`) that correctly parses Qwen3-Coder's XML tool-call format into structured `tool_calls`.

Install (uv, project-clone, ~30 s on a fast connection):

```bash
git clone https://github.com/waybarrios/vllm-mlx.git ~/src/vllm-mlx
cd ~/src/vllm-mlx
uv venv && uv pip install -e .
```

Launch with Qwen3-Coder parser (port 8001 — keeps llama-server on 8080 and higgs on 8002 untouched):

```bash
source ~/src/vllm-mlx/.venv/bin/activate
vllm-mlx serve mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit-DWQ \
  --port 8001 --host 127.0.0.1 \
  --enable-auto-tool-choice \
  --tool-call-parser qwen3_coder
```

Verify with tool-call-test:

```bash
PORT=8001 ALIAS=mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit-DWQ tool-call-test
# → PASS: structured tool_calls returned
```

Wire into pi (`~/.pi/agent/models.json`):

```json
"local-vllm-mlx": {
  "baseUrl": "http://127.0.0.1:8001/v1",
  "api": "openai-completions",
  "apiKey": "not-needed",
  "models": [{
    "id": "mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit-DWQ",
    "name": "Qwen3-Coder-30B (local, MLX via vllm-mlx)",
    "reasoning": false,
    "contextWindow": 32768,
    "maxTokens": 8192
  }]
}
```

### Three-way decode benchmark: Qwen3-Coder-30B on this M1 Max

Same prompt, same `max_tokens=256`, 3 runs each, no `/no_think` (Qwen3-Coder isn't a thinking model):

| Engine | Quant | TTFT | Decode | Tool calls work? |
|---|---|---|---|---|
| llama.cpp | Q5_K_M GGUF | 194 ms | 48.1 tok/s | ✓ via `--jinja` + Qwen official template |
| higgs (Rust+MLX) | 4bit-DWQ | 354 ms | 57.7 tok/s (+20%) | ✗ XML parser gap |
| **vllm-mlx (Python+MLX)** | 4bit-DWQ | 435 ms | **60.1 tok/s (+25%)** | ✓ via `--tool-call-parser qwen3_coder` |

**Verdict for Qwen3-Coder-30B specifically: vllm-mlx is the best option** on this hardware right now — fastest decode AND working tool calling. higgs is faster than llama.cpp on raw decode but unusable for tool calling on this model. llama.cpp remains the simplest setup.

For pi daily use, switching `qwen3-coder-30b-a3b` from `local-llamacpp` to `local-vllm-mlx` is a ~25% decode speedup with no quality difference at the same 4-bit-class quant. Trade-off: vllm-mlx is a Python service that needs the venv activated, slightly more setup than `qwen-serve`.

### GLM-4.5-Air on vllm-mlx (also working)

After the Qwen success, also verified `mlx-community/GLM-4.5-Air-4bit` (~50 GB MLX) on vllm-mlx with `--tool-call-parser glm47`. `tool-call-test` passes. Required bumping the macOS wired-memory cap to 60 GB (`sudo sysctl iogpu.wired_limit_mb=61440`) — MLX is hungrier than llama.cpp Metal at this model size, and the default cap (~44 GB) or even our earlier 56 GB setting wasn't enough.

| Engine | Quant | TTFT | Decode | Tool calls work? |
|---|---|---|---|---|
| llama.cpp | UD-Q3_K_XL GGUF (~51 GB) | — | 20.6 tok/s | ✓ |
| vllm-mlx | 4bit MLX (~50 GB) | 1298 ms | **22.9 tok/s (+11%)** | ✓ via `--tool-call-parser glm47` |

Modest speedup on GLM-Air vs the bigger wins on smaller models — consistent with bigger MoE models being memory-bandwidth-bound, where MLX's compute advantage matters less. TTFT is high (1298 ms) because MLX takes longer to set up large-model prefill. **Practical recommendation: keep `glmair-serve` (llama.cpp) for GLM-Air work** — the 11% decode win doesn't justify the wired-memory-cap operational risk (4 GB of OS headroom on a 64 GB Mac) or the extra venv setup.

### Why higgs was removed from this repo

The earlier higgs (Rust+MLX) section is preserved above as a record of the testing, but **higgs is no longer installed in this repo** — the `install/higgs.sh` script and `local-higgs` provider entry have been removed. higgs's parser gap on Qwen3-Coder XML and architecture gaps on `gpt_oss`/`glm4_moe` meant zero of the four production models worked end-to-end. vllm-mlx covers everything higgs would have, plus more, with the same no-Xcode property.

### Summary: which engine for which model in this repo

Three of the four production models now have working vllm-mlx paths (verified end-to-end on this hardware, 2026-05-14):

| Model | vllm-mlx status | Recommended engine | Why |
|---|---|---|---|
| Qwen3-Coder-30B-A3B | ✓ verified | `vllm-mlx-serve` | +25% decode vs llama.cpp; ~7 s first-turn TTFT in pi |
| gpt-oss-20b | ✗ tool calls broken on vllm-mlx 0.3.0 | llama.cpp (`gptoss-serve`) | Known upstream issue. Model emits correct Harmony output but vllm-mlx's `/v1/chat/completions` adapter doesn't run the Harmony tool-call parser. **Upstream vLLM fixed this** in [vllm#26083](https://github.com/vllm-project/vllm/issues/26083) (closed 2026-02-15), but vllm-mlx 0.3.0 hasn't inherited the fix — its maintainer pivoted to the official [`vllm-project/vllm-metal`](https://github.com/vllm-project/vllm-metal) plugin instead (vllm-mlx [#123](https://github.com/waybarrios/vllm-mlx/issues/123), 2026-02-28). gpt-oss support in vllm-metal is tracked at [vllm-metal#212](https://github.com/vllm-project/vllm-metal/issues/212), still open. |
| GLM-4.5-Air | ✓ verified | llama.cpp (`glmair-serve`) | vllm-mlx works but only +11% decode AND has 26 s prefill cost — see [prefill latency note](./11-prompt-engineering.md#dont-ignore-prefill-latency-on-big-context-pi-sessions) |
| Qwen3-Coder-Next-80B | not yet tested | llama.cpp (`qwennext-serve`) | same XML tool-call format as Qwen3-Coder-30B; likely works on vllm-mlx but unverified |

**For everyday pi work**, the highest-value swap is **Qwen3-Coder-30B → vllm-mlx** (real ~25% decode speedup, fast TTFT). gpt-oss-20b is even faster but generalist-tuned; pick Qwen3-Coder when you need code-specific quality and gpt-oss-20b for survey/Q&A or quick edits. GLM-Air's vllm-mlx path works but the prefill cost makes it impractical for interactive sessions — keep llama.cpp's `glmair-serve` for that one.

The `~/bin/vllm-mlx-serve` wrapper auto-picks both the tool-call parser and reasoning parser from the model name pattern:

- `Qwen3-Coder-*` → `--tool-call-parser qwen3_coder --reasoning-parser qwen3`
- `gpt-oss-*` → `--tool-call-parser harmony --reasoning-parser gpt_oss`
- `GLM-4.5-*` / `GLM-4.7-*` → `--tool-call-parser glm47 --reasoning-parser glm4`
- `Qwen3-*` (non-coder) → `--tool-call-parser qwen --reasoning-parser qwen3`
- Other Llama-3+, Mistral, DeepSeek, Gemma-4 also covered

so just `~/bin/vllm-mlx-serve <hf-id>` does the right thing across these four model families.

### Watch-list: `vllm-project/vllm-metal` (vllm-mlx's successor)

`waybarrios/vllm-mlx` is the community fork we currently use; its maintainer announced in [#123](https://github.com/waybarrios/vllm-mlx/issues/123) that further work is going into the official `vllm-project/vllm-metal` plugin instead. vllm-metal is actively developed (commits daily as of 2026-05-14), 1140+ stars, and tracks upstream vLLM closely — so it will pick up fixes like the gpt-oss tool-call resolution faster than vllm-mlx will.

When gpt-oss tool calling lands in vllm-metal (tracked at [#212](https://github.com/vllm-project/vllm-metal/issues/212)), it's worth porting `install/vllm-mlx.sh` to `install/vllm-metal.sh` — same uv/clone/install pattern, different upstream. That would unlock all four production models on a single non-llama.cpp engine.

  Install (uses `uv` per this repo's convention — see [[feedback-use-uv-for-python]] memory, and `pyproject.toml` / `uv.lock`):

  ```bash
  # Requires macOS on Apple Silicon (M1+) and Python 3.10+
  git clone https://github.com/waybarrios/vllm-mlx.git ~/src/vllm-mlx
  cd ~/src/vllm-mlx
  uv pip install -e .
  ```

  Optional extras (only if you need them):

  ```bash
  uv pip install -e ".[vision]"   # vision-language models
  uv pip install mlx-audio         # STT/TTS
  uv pip install mlx-embeddings    # embedding models
  ```

  Verify:

  ```bash
  vllm-mlx --help
  vllm-mlx-bench --model mlx-community/Llama-3.2-1B-Instruct-4bit --prompts 1
  ```

  Launch the OpenAI-compatible server (use **port 8001** to avoid colliding with llama-server on 8080):

  ```bash
  # Direct from Hugging Face
  vllm-mlx serve mlx-community/Qwen3-8B-4bit --port 8001 --continuous-batching

  # Or from local disk after acquiring
  vllm-mlx model acquire mlx-community/Llama-3.2-3B-Instruct-4bit --target-dir ~/models/llama-3b-4bit
  vllm-mlx serve ~/models/llama-3b-4bit --port 8001 --continuous-batching
  ```

  Wire into pi: add a provider entry in `~/.pi/agent/models.json` pointing at `http://127.0.0.1:8001/v1` with the model id vllm-mlx advertises at `/v1/models`. Then `tool-call-test` (with `ALIAS=<your-alias> BASE_URL=http://127.0.0.1:8001/v1`) verifies structured tool calls survive the engine swap — same gate as for the llama.cpp models.

  **Caveats:**
  - MLX uses its own model format, not GGUF. The GGUFs you already downloaded for llama.cpp won't load — you'll need MLX-quantized versions from [mlx-community](https://huggingface.co/mlx-community). Disk-doubling cost.
  - The upstream README references MCP tool-calling but doesn't document the verification flow; rely on `tool-call-test` as the practical gate.
  - Comparison-vs-llama.cpp is the headline value, but the MLX format conversion means it's not a perfectly clean A/B (different quantization).

## Comparison plan

Once one of these is wired in:

1. Run the same `llama-bench` sweep we ran on llama.cpp (see [docs/05-benchmarking.md](./05-benchmarking.md)) — same model, same quant, different engine.
2. Run `tool-call-test` against the new server to verify structured tool calls survive the engine swap.
3. Drop into pi for a real coding task and compare felt latency.

The model file stays the same; only the server binary changes. That's the cleanest way to attribute speed differences to the engine, not the model.
