# pi_qwen

Run [pi](https://pi.dev) — a minimal terminal coding agent — against a **local** [Qwen3-Coder-30B-A3B-Instruct](https://huggingface.co/Qwen/Qwen3-Coder-30B-A3B-Instruct) model served by [llama.cpp](https://github.com/ggml-org/llama.cpp), all on Apple Silicon.

No API keys. No cloud round-trips. All inference on your machine.

## Why this combo

- **Qwen3-Coder-30B-A3B-Instruct** is a Mixture-of-Experts coding model: 30B total parameters, but only ~3B are active per token. That makes it surprisingly fast on consumer Apple Silicon while keeping the quality of a much larger model, and the coder-tuned weights track function-level and repo-level tasks better than the base Qwen3-30B-A3B.
- **llama.cpp** has the most mature Metal backend and ships precompiled via Homebrew — no Xcode required.
- **pi** is an OpenAI-API-compatible coding agent, so it talks to llama.cpp's HTTP server like any other provider.

## Tested on

- Apple M1 Max, 64 GB RAM, macOS 26.3 (`arm64`)
- llama.cpp via Homebrew (`b9100`)
- pi `latest`
- Quant: `Qwen3-Coder-30B-A3B-Instruct-Q5_K_M.gguf` (~21 GB on disk, ~24 GB resident with 32k context)

Measured throughput on this hardware: **~594 tok/s prefill (pp512)**, **~409 tok/s prefill (pp8192)**, and **~51 tok/s decode (tg128)**. See [Benchmarking](#benchmarking).

Should work on any Apple Silicon Mac with ≥ 32 GB RAM. Bigger context windows or higher-bit quants need more.

## Quickstart

```bash
# 1. Install llama.cpp (Metal-enabled, precompiled)
brew install llama.cpp

# 2. Install pi
curl -fsSL https://pi.dev/install.sh | sh

# 3. Download the model (~21 GB)
pip install -U "huggingface_hub[cli]" hf_transfer
mkdir -p ~/models/qwen3-coder-30b-a3b && cd ~/models/qwen3-coder-30b-a3b
HF_HUB_ENABLE_HF_TRANSFER=1 hf download \
  unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF \
  Qwen3-Coder-30B-A3B-Instruct-Q5_K_M.gguf --local-dir .

# 4. Install the helper scripts
mkdir -p ~/bin
cp scripts/qwen-serve scripts/qwen-test ~/bin/
chmod +x ~/bin/qwen-serve ~/bin/qwen-test
# Add ~/bin to PATH if you haven't already:
# echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc

# 5. Install the pi provider config
mkdir -p ~/.pi/agent
cp config/models.json ~/.pi/agent/models.json

# 6. Start the server (leave it running)
qwen-serve

# 7. From another terminal, smoke-test
qwen-test "reply with just: hello"

# 8. Run pi against the local model
cd /path/to/some/project
pi --model qwen3-coder-30b-a3b
```

## Daily use

Once everything from Quickstart is in place, the day-to-day cycle is two commands in two terminals:

```bash
# Terminal 1 — start the server (leave it running)
qwen-serve

# Terminal 2 — drop into pi against the local model
cd /path/to/your/project
pi --model qwen3-coder-30b-a3b
```

Exit pi with `/exit` or Ctrl-D. The server keeps running in Terminal 1 across multiple pi sessions; stop it with Ctrl-C when you're done for the day.

## How the pieces fit

```
┌─────────┐    HTTP /v1/chat/completions   ┌──────────────┐    Metal    ┌──────────┐
│   pi    │ ──────────────────────────────▶│ llama-server │ ──────────▶ │   GPU    │
│ (agent) │                                │  (llama.cpp) │             │ (M-chip) │
└─────────┘                                └──────────────┘             └──────────┘
                                                  ▲
                                                  │ reads
                                                  ▼
                                         ~/models/...Q5_K_M.gguf
```

pi sees an OpenAI-compatible endpoint. llama-server does the actual inference on Metal. Your model file sits on disk and is memory-mapped at load time.

## The scripts

### `qwen-serve`
Starts `llama-server` with the flag set this repo has settled on. Honors env-var overrides:

```bash
qwen-serve                                  # defaults
PORT=8081 CTX=65536 qwen-serve              # bigger context, different port
MODEL=~/models/other.gguf qwen-serve        # swap the model file
ALIAS=my-model qwen-serve                   # change the model id pi sees
```

Key flags it sets:
- `-ngl 99` — offload all layers to Metal GPU. Free on Apple Silicon since memory is unified.
- `-c 32768` — 32k context. Bump to 65536/131072 if you need long sessions and have headroom.
- `-fa on` — flash attention (new llama.cpp requires explicit `on`/`off`/`auto`).
- `--jinja` — use the model's own chat template.
- `--temp 0.6 --top-p 0.95 --top-k 20` — Qwen's official sampler recommendations.

### `qwen-test`
Single-shot prompt against the running server. Useful for sanity checks.

```bash
qwen-test                          # default: "reply with just: hello"
qwen-test "what is 2+2"            # custom prompt
PORT=8081 qwen-test "ping"         # different port
```

## Choosing a quant

| Quant     | File size | Quality | Notes                                 |
|-----------|-----------|---------|---------------------------------------|
| Q4_K_M    | ~18 GB    | Good    | Default if RAM is tight (32 GB Macs). |
| **Q5_K_M**| ~21 GB    | Better  | Sweet spot for 64 GB+ Macs.           |
| Q6_K      | ~25 GB    | Great   | Marginal gain over Q5; rarely worth.  |
| Q8_0      | ~32 GB    | Near-FP | Diminishing returns; long load times. |

Memory budget at 32k context ≈ model size + ~3 GB KV cache + ~1 GB overhead. Add ~3 GB per doubling of context.

## Troubleshooting

### Download is glacial (single-digit MB/s)
Set up `hf_transfer` and an HF token:
```bash
pip install -U hf_transfer
export HF_HUB_ENABLE_HF_TRANSFER=1
export HF_TOKEN=hf_xxxxxxxxxxxx   # from https://huggingface.co/settings/tokens
```

### `error: unknown value for --flash-attn`
Newer llama.cpp requires `-fa on` (or `off`/`auto`), not bare `-fa`. The script in this repo already uses the new form.

### pi doesn't see the model
```bash
pi --list-models
jq . ~/.pi/agent/models.json   # validate JSON
curl -s http://127.0.0.1:8080/v1/models | jq   # confirm server is up
```
The model `id` in `models.json` must match the `-a` alias passed to `llama-server` (both are `qwen3-coder-30b-a3b` here).

### Garbled or template-broken output
You probably forgot `--jinja`. Without it llama.cpp falls back to a generic template and Qwen3's chat tokens get mangled.

### Out of memory at load
Drop the quant (Q5_K_M → Q4_K_M) or the context (`CTX=16384 qwen-serve`).

## Alternative: mistral.rs (Rust)

[mistral.rs](https://github.com/EricLBuehler/mistral.rs) is the Rust-native inference server. It supports Qwen3 MoE and Metal, and also serves an OpenAI-compatible API. The only structural difference for pi is the `baseUrl` and the model `id` (mistral.rs reports the loaded model as `default` unless overridden).

The catch on macOS: building it requires the Metal shader compiler, which ships only with **full Xcode** (not Command Line Tools). If you don't already have Xcode installed, llama.cpp is the friction-free path. If you do:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
cargo install --git https://github.com/EricLBuehler/mistral.rs mistralrs-server --features metal

mistralrs-server --port 8080 gguf \
  -m ~/models/qwen3-coder-30b-a3b \
  -f Qwen3-Coder-30B-A3B-Instruct-Q5_K_M.gguf
```

Then change `id` to `default` in `models.json` and you're off.

## Benchmarking

### Throughput (`bench/throughput.sh`)

Reports raw inference speed via `llama-bench` — prompt processing (`pp`, prefill) and token generation (`tg`, decode), both in tok/s. This measures the model + your hardware, not pi.

```bash
# Stop qwen-serve first so the GPU isn't contended
./bench/throughput.sh
```

For a richer sweep — multiple prompt sizes, multiple generation lengths, and a combined prefill+decode test that resembles a real pi turn — call `llama-bench` directly:

```bash
llama-bench \
  -m ~/models/qwen3-coder-30b-a3b/Qwen3-Coder-30B-A3B-Instruct-Q5_K_M.gguf \
  -p 512,2048,8192 \
  -n 128,512 \
  -pg 8192,128 \
  -ngl 99 -fa 1 -r 3
```

Real run on Apple M1 Max, 64 GB, llama.cpp build `2e97c5f96 (9100)`:

```
| model                          |      size |  params | backend  | threads | fa |          test |             t/s |
| ------------------------------ | --------: | ------: | -------- | ------: | -: | ------------: | --------------: |
| qwen3moe 30B.A3B Q5_K - Medium | 20.23 GiB | 30.53 B | BLAS,MTL |       8 |  1 |         pp512 |   593.80 ± 4.38 |
| qwen3moe 30B.A3B Q5_K - Medium | 20.23 GiB | 30.53 B | BLAS,MTL |       8 |  1 |        pp2048 |   554.40 ± 0.51 |
| qwen3moe 30B.A3B Q5_K - Medium | 20.23 GiB | 30.53 B | BLAS,MTL |       8 |  1 |        pp8192 |   409.13 ± 7.86 |
| qwen3moe 30B.A3B Q5_K - Medium | 20.23 GiB | 30.53 B | BLAS,MTL |       8 |  1 |         tg128 |    50.76 ± 0.21 |
| qwen3moe 30B.A3B Q5_K - Medium | 20.23 GiB | 30.53 B | BLAS,MTL |       8 |  1 |         tg512 |    50.00 ± 0.11 |
| qwen3moe 30B.A3B Q5_K - Medium | 20.23 GiB | 30.53 B | BLAS,MTL |       8 |  1 |  pp8192+tg128 |   356.51 ± 2.71 |
```

Reading the numbers:
- **`pp512` → `pp8192`** (594 → 409 tok/s): prefill cost grows super-linearly. Long prompts dominate wall-clock time, not decode.
- **`tg128` ≈ `tg512`** (51 vs 50 tok/s): decode is steady regardless of generation length.
- **`pp8192+tg128`** (357 tok/s effective): combined prefill+decode for a realistic pi turn. This is closer to what you'll feel in practice than `pp512` alone.

MoE throughput moves with quant, batch size, context length, and how much else the GPU is doing.

Overrides for the wrapper:
```bash
PP=2048 TG=256 REPS=5 ./bench/throughput.sh     # bigger batches, more reps
MODEL=~/models/other.gguf ./bench/throughput.sh # benchmark a different model
NGL=0 ./bench/throughput.sh                     # CPU-only baseline (slow)
```

Run this once after install to confirm your hardware is performing, and again after any quant/flag change to catch regressions.

### Other benchmarks worth knowing about

- **Latency / time-to-first-token** — measures the path pi actually walks. Send timed requests to `/v1/chat/completions` and read the `timings` block llama-server returns.
- **Agent quality** — public coding-agent benchmarks like [Aider's polyglot eval](https://aider.chat/docs/leaderboards/) or HumanEval. They measure the model, not pi-with-the-model.
- **Your own prompt set** — the only thing that measures *your* workflow. A handful of representative tasks from your real work, run twice, eyeballed.

## Layout of this repo

```
pi_qwen/
├── README.md            # this file
├── LICENSE              # MIT
├── scripts/
│   ├── qwen-serve       # start llama-server with sensible defaults
│   └── qwen-test        # one-shot smoke test
├── bench/
│   └── throughput.sh    # llama-bench wrapper for pp/tg tok/s
└── config/
    └── models.json      # pi provider config (copy to ~/.pi/agent/)
```

## Credits

- [Qwen team](https://qwenlm.github.io/) for the base model
- [Unsloth](https://huggingface.co/unsloth) for the GGUF quants used here
- [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) for the inference engine
- [pi](https://pi.dev) for the agent

## License

MIT — see [LICENSE](LICENSE).
