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
| `mlx-community/Qwen3-1.7B-4bit` | ✓ PASS | Structured `tool_calls` returned cleanly for `get_weather`. Verified end-to-end with this exact command: `PORT=8002 ALIAS=qwen3-1.7b tool-call-test`. |
| `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit` | _pending download_ | MLX equivalent of the repo's default llama.cpp model. Same architecture family as Qwen3-1.7B, so high prior on tool calling working. |
| `mlx-community/gpt-oss-20b-MXFP4-Q4` | _pending download_ | MLX equivalent of `local-gpt-oss-20b`. Uses OpenAI's Harmony format — higgs needs to render Harmony correctly for tool calls to fire. |
| `mlx-community/GLM-4.5-Air-4bit` | _pending download_ | MLX equivalent of `local-glm-4.5-air`. GLM has its own chat template format; verifying higgs handles it. |
| `mlx-community/Llama-3.2-1B-Instruct-4bit` | ✗ FAIL | Jinja template error: `too many arguments (in chat:61)`. Not a higgs bug — Meta's Llama-3.2 1B doesn't ship a tool-call-aware chat template (tool support starts at 3B+). Same failure shape as the DeepSeek-Coder-V2-Lite rejection in [`docs/02-models.md`](./02-models.md#tested-and-rejected). |

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
