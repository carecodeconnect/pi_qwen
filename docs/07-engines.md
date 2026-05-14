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

## MLX (not Rust, but the no-Xcode path)

- **[vllm-mlx](https://github.com/waybarrios/vllm-mlx)** — MLX backend with an OpenAI + Anthropic-compatible HTTP server, baked-in MCP tool calling (12 parsers including OpenAI, Anthropic, Gemini, Qwen, DeepSeek, Gemma), continuous batching, and vision/audio support. Reports 400+ tok/s on M-series for small models and 10–30% faster than llama.cpp Metal on 70B+ models.

  **Why this matters here:** MLX is Apple's own ML framework, distributed as pre-built Python wheels with the Metal shaders already compiled. **No Xcode and no Apple ID required to install.** That makes vllm-mlx the only practical alternate-engine path on this hardware if mistral.rs / Crane / candle-vllm are blocked by the Xcode requirement.

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
