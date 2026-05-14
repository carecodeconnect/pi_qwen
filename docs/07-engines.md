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

## Adjacent: MLX (not Rust, but Apple-native)

- **[vllm-mlx](https://github.com/waybarrios/vllm-mlx)** — MLX backend with OpenAI + Anthropic-compatible server, baked-in MCP tool calling, reports 400+ tok/s on M-series for some models. Not Rust, but if the real goal is "swap llama.cpp for something faster on this hardware," MLX is reported 10–30% faster than llama.cpp Metal on 70B+ models. Worth a comparison run alongside the Rust engines.

## Comparison plan

Once one of these is wired in:

1. Run the same `llama-bench` sweep we ran on llama.cpp (see [docs/05-benchmarking.md](./05-benchmarking.md)) — same model, same quant, different engine.
2. Run `tool-call-test` against the new server to verify structured tool calls survive the engine swap.
3. Drop into pi for a real coding task and compare felt latency.

The model file stays the same; only the server binary changes. That's the cleanest way to attribute speed differences to the engine, not the model.
