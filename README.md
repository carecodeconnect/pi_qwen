# pi_qwen

Run [pi](https://pi.dev) — a minimal terminal coding agent — against a **local** [Qwen3-Coder-30B-A3B-Instruct](https://huggingface.co/Qwen/Qwen3-Coder-30B-A3B-Instruct) model served by [llama.cpp](https://github.com/ggml-org/llama.cpp), all on Apple Silicon.

No API keys. No cloud round-trips. All inference on your machine.

![pi + Qwen3-Coder demo](demo/pi-qwen.gif)

## Why this combo

- **Qwen3-Coder-30B-A3B-Instruct** is a Mixture-of-Experts coding model: 30B total parameters, but only ~3B are active per token. That makes it surprisingly fast on consumer Apple Silicon while keeping the quality of a much larger model, and the coder-tuned weights track function-level and repo-level tasks better than the base Qwen3-30B-A3B.
- **llama.cpp** has the most mature Metal backend and ships precompiled via Homebrew — no Xcode required.
- **pi** is an OpenAI-API-compatible coding agent, so it talks to llama.cpp's HTTP server like any other provider.

## Tested on

- Apple M1 Max, 64 GB RAM, macOS 26.3 (`arm64`)
- llama.cpp via Homebrew (`b9100`)
- pi `latest`
- Quant: `Qwen3-Coder-30B-A3B-Instruct-Q5_K_M.gguf` (~21 GB on disk, ~37 GB resident with the default 131k context)

Measured throughput on this hardware: **~594 tok/s prefill (pp512)**, **~409 tok/s prefill (pp8192)**, and **~51 tok/s decode (tg128)**. See [Benchmarking](#benchmarking).

Should work on any Apple Silicon Mac with ≥ 32 GB RAM. Bigger context windows or higher-bit quants need more.

## Python tooling (uv)

The only Python this repo needs is the `hf` CLI (from `huggingface_hub`) and `hf_transfer` for fast multi-stream downloads. Both live in a uv-managed venv pinned by `pyproject.toml` / `uv.lock` — no global `pip install`, no PEP 668 fights with system Python.

```bash
# One-time setup
curl -LsSf https://astral.sh/uv/install.sh | sh    # install uv if you don't have it
cd ~/projects/pi_qwen
uv sync                                             # creates .venv/, installs deps from lockfile

# Run hf commands inside the project venv
uv run hf --version
HF_HUB_ENABLE_HF_TRANSFER=1 uv run hf download <repo> <file> --local-dir <dest>
```

If you'd rather have `hf` on PATH without prefixing `uv run`, two options:
- `uv tool install huggingface_hub` — puts `hf` in `~/.local/bin` via uv's tool venv.
- Or activate the project venv: `source ~/projects/pi_qwen/.venv/bin/activate`.

## Hugging Face authentication

The Unsloth GGUF used below is public, so a token isn't strictly required — but logging in lifts anonymous rate limits and is the path of least resistance if you ever swap in a gated model (Meta, Mistral, some Qwen variants). The [HF CLI docs](https://huggingface.co/docs/huggingface_hub/en/guides/cli) cover this in full.

1. **Create a token** at https://huggingface.co/settings/tokens. A *Read* token is enough for downloads.
2. **Log in once** — `huggingface_hub` stores the token in `~/.cache/huggingface/token` so future commands pick it up automatically:
   ```bash
   uv run hf auth login           # paste the token when prompted
   uv run hf auth whoami          # verify
   ```

Alternatively, export `HF_TOKEN` in your shell rc — useful in scripted/CI contexts:
```bash
export HF_TOKEN=hf_xxxxxxxxxxxx
```

## Quickstart

```bash
# 1. Install llama.cpp (Metal-enabled, precompiled)
brew install llama.cpp

# 2. Install pi (needs Node ≥ 20.18.1; install via `brew install node` or nvm
#    if you don't have it, or hit "pi install fails" in Troubleshooting)
curl -fsSL https://pi.dev/install.sh | sh

# 3. Install uv (Python project/dependency manager) if you don't have it
curl -LsSf https://astral.sh/uv/install.sh | sh

# 4. Sync this repo's Python deps — gets you `hf` (huggingface_hub CLI) and
#    hf_transfer (multi-stream downloads), pinned and reproducible
cd ~/projects/pi_qwen && uv sync

# 5. Download the model (~21 GB). `uv run` invokes hf from the project venv
mkdir -p ~/models/qwen3-coder-30b-a3b && cd ~/models/qwen3-coder-30b-a3b
HF_HUB_ENABLE_HF_TRANSFER=1 uv run --project ~/projects/pi_qwen \
  hf download unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF \
  Qwen3-Coder-30B-A3B-Instruct-Q5_K_M.gguf --local-dir .

# 6. Install the helper scripts
mkdir -p ~/bin
cp scripts/qwen-serve scripts/qwen-test scripts/fetch-template ~/bin/
chmod +x ~/bin/qwen-serve ~/bin/qwen-test ~/bin/fetch-template
# Add ~/bin to PATH if you haven't already:
# echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc

# 7. Install the pi provider config
mkdir -p ~/.pi/agent
cp config/models.json ~/.pi/agent/models.json

# 8. Fetch Qwen's official chat template (needed for tool calling — see "Tool calling" below)
fetch-template

# 9. Start the server (leave it running)
qwen-serve

# 10. From another terminal, smoke-test
qwen-test "reply with just: hello"

# 11. Run pi against the local model
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
qwen-serve                                  # defaults (131k context)
PORT=8081 CTX=65536 qwen-serve              # smaller context, different port
CTX=262144 qwen-serve                       # push it — uses ~24 GB KV cache
MODEL=~/models/other.gguf qwen-serve        # swap the model file
ALIAS=my-model qwen-serve                   # change the model id pi sees
```

Key flags it sets:
- `-ngl 99` — offload all layers to Metal GPU. Free on Apple Silicon since memory is unified.
- `-c 131072` — 131k context. Sized for a 64 GB Apple Silicon Mac; drop to 32768/65536 on 32 GB machines, or bump to 262144 if you have the headroom.
- `-fa on` — flash attention (new llama.cpp requires explicit `on`/`off`/`auto`).
- `--jinja` — render the chat template (Qwen's, via `--chat-template-file`).
- `--chat-template-file <path>` — load Qwen's official chat template instead of the GGUF-embedded one. See [Tool calling](#tool-calling) for why.
- `--temp 0.6 --top-p 0.95 --top-k 20` — Qwen's official sampler recommendations.

### `qwen-test`
Single-shot prompt against the running server. Useful for sanity checks.

```bash
qwen-test                                        # default: "reply with just: hello"
qwen-test "what is 2+2"                          # custom prompt
ALIAS=local-gpt-oss-20b qwen-test "ping"         # works against any alias
```

### `tool-call-test`
Model-agnostic check that the running server returns structured `tool_calls` (the same field pi reads). Defines a `get_weather` tool and prompts the model to call it; passes only if `choices[0].message.tool_calls` is present in the response.

```bash
ALIAS=qwen3-coder-30b-a3b   tool-call-test       # against Qwen
ALIAS=local-gpt-oss-20b           tool-call-test   # against gpt-oss
ALIAS=local-devstral-small-2507   tool-call-test   # against Devstral
```

If this fails, pi will not see tool calls from that model either — fix the chat-template wiring before running pi.

### `serve-stop`
Kills whatever llama-server is currently bound to port 8080 (override with `PORT=…`). Useful when switching between `qwen-serve` / `gptoss-serve` / `devstral-serve`, since only one server can hold the port at a time.

```bash
serve-stop                       # frees port 8080
PORT=8081 serve-stop             # different port
```

### `fetch-template`
Downloads Qwen's official chat template from HuggingFace and writes it to `~/models/qwen3-coder-30b-a3b/templates/qwen3-coder-official.jinja`, where `qwen-serve` looks for it. Run once after install. See [Tool calling](#tool-calling) for why this is needed.

```bash
fetch-template                                              # defaults
DEST=~/other/place/template.jinja fetch-template            # custom location
```

### `gptoss-serve` (alternate model)
Serves OpenAI's [`gpt-oss-20b`](https://huggingface.co/openai/gpt-oss-20b) — a 21B MoE (~3.6B active) with reasoning and built-in tool calling. The GGUF ships in MXFP4 format (~12 GB), the native quant OpenAI released; no further quantization needed and no chat-template override required.

```bash
# Install once
mkdir -p ~/models/gpt-oss-20b
HF_HUB_ENABLE_HF_TRANSFER=1 uv run --project ~/projects/pi_qwen hf download \
  ggml-org/gpt-oss-20b-GGUF gpt-oss-20b-mxfp4.gguf \
  --local-dir ~/models/gpt-oss-20b
cp scripts/gptoss-serve ~/bin/ && chmod +x ~/bin/gptoss-serve

# Serve (only one llama-server can hold port 8080 at a time — stop qwen-serve first)
gptoss-serve

# In pi
pi --model local-gpt-oss-20b
```

Defaults: `CTX=131072`, sampler temp 1.0 / top-p 1.0 (gpt-oss is reasoning-tuned and recommends near-deterministic sampling controlled by `reasoning_effort` in the system prompt rather than temperature).

The `local-` prefix on the model id avoids a collision with pi's built-in `gpt-oss-20b` entries (which route to OpenAI / Fireworks / Cloudflare / Bedrock). See [Troubleshooting → pi routes to a cloud provider](#pi-routes-to-a-cloud-provider-instead-of-localhost).

### `devstral-serve` (alternate model)
Serves Mistral × All Hands AI's [`Devstral-Small-2507`](https://huggingface.co/mistralai/Devstral-Small-2507) — a 24B dense model purpose-tuned for agentic coding (SWE-bench leaderboard). Uses Unsloth's dynamic Q5 quant (UD-Q5_K_XL, ~17 GB) for a fair comparison against the Qwen Q5_K_M baseline.

```bash
# Install once
mkdir -p ~/models/devstral-small-2507
HF_HUB_ENABLE_HF_TRANSFER=1 uv run --project ~/projects/pi_qwen hf download \
  unsloth/Devstral-Small-2507-GGUF Devstral-Small-2507-UD-Q5_K_XL.gguf \
  --local-dir ~/models/devstral-small-2507
cp scripts/devstral-serve ~/bin/ && chmod +x ~/bin/devstral-serve

# Serve (stop other llama-server processes first)
devstral-serve

# In pi
pi --model local-devstral-small-2507
```

Defaults: `CTX=131072`, sampler temp 0.15 (Mistral's recommendation — lower than Qwen's 0.6 for agent stability). The GGUF's embedded Mistral chat template handles tool calls correctly out of the box; no `--chat-template-file` override needed.

The `local-` prefix on the model id avoids a collision with pi's built-in `devstral-small-2507` entry (which routes to `api.mistral.ai` and requires a `MISTRAL_API_KEY`). See [Troubleshooting → pi routes to a cloud provider](#pi-routes-to-a-cloud-provider-instead-of-localhost).

## Tool calling

pi needs the model to emit **structured tool calls**, not text. By default, the Unsloth Q5_K_M GGUF ships with an embedded chat template that has a tool-call bug: the model produces inner `<function=...>` blocks without the outer `<tool_call>` wrapper Qwen expects. llama-server then can't parse those back into the `tool_calls` field of the response, pi sees raw text, no tools execute, and the agent appears to hallucinate that it's running commands.

The fix is to load Qwen's official chat template explicitly via `--chat-template-file`. That's what `fetch-template` downloads and `qwen-serve` wires in.

Verify it's wired up correctly after starting `qwen-serve`:

```bash
curl -s http://127.0.0.1:8080/props | python3 -c "
import sys, json
d = json.load(sys.stdin)
ct = d.get('chat_template','')
print('template loaded:', bool(ct), 'length:', len(ct))
print('first line:', ct.split(chr(10))[0])
"
```

If the first line is `{% macro render_extra_keys(json_dict, handled_keys) %}` you've got Qwen's official template. If it starts with an Unsloth copyright header, the override didn't take — re-run `fetch-template` and re-check the file path in `qwen-serve`.

Smoke test in pi: ask `explain the purpose of this codebase` from inside this repo. You should see pi actually execute `find` and `read README.md` as tool calls (rendered as `$ find ...` and `read README.md` blocks in the TUI), not raw `<function=bash>` XML.

### Using Tools with pi/qwen

This setup is designed to work with pi's tool calling capabilities. The key configuration for enabling tool usage includes:

1. **Proper Template Loading**: The `fetch-template` script downloads Qwen's official chat template which fixes tool-call format issues in the GGUF's embedded template.

2. **Model Configuration**: The `models.json` configuration file in `config/` properly maps the model ID to the server alias.

3. **Example Usage**: Once the server is running, you can test tool usage in pi by asking it to perform tasks like:
   ```
   pi --model qwen3-coder-30b-a3b
   ```

## Choosing a quant

| Quant     | File size | Quality | Notes                                 |
|-----------|-----------|---------|---------------------------------------|
| Q4_K_M    | ~18 GB    | Good    | Default if RAM is tight (32 GB Macs). |
| **Q5_K_M**| ~21 GB    | Better  | Sweet spot for 64 GB+ Macs.           |
| Q6_K      | ~25 GB    | Great   | Marginal gain over Q5; rarely worth.  |
| Q8_0      | ~32 GB    | Near-FP | Diminishing returns; long load times. |
| Q3_K_M    | ~15 GB    | Fair    | For users with very limited disk space. |

Memory budget ≈ model size + KV cache + ~1 GB overhead. KV cache for this model is ~96 KB/token at fp16, so:

| Context | KV cache | Total RAM (Q5_K_M) | Fits on   |
|--------:|---------:|-------------------:|-----------|
|     32k |    ~3 GB |             ~25 GB | 32 GB Mac |
|     64k |    ~6 GB |             ~28 GB | 32 GB Mac (tight) |
| **131k**|   **~12 GB** |          **~34 GB** | **64 GB Mac (default)** |
|    262k |   ~24 GB |             ~46 GB | 64 GB Mac (aggressive) |

Tip: add `--cache-type-k q8_0 --cache-type-v q8_0` to `llama-server` (in `qwen-serve`) to halve KV-cache memory at negligible quality cost — that lets a 64 GB Mac comfortably reach 262k, or push to ~512k.

## Troubleshooting

### Download is glacial (single-digit MB/s)
Make sure `hf_transfer` is being engaged. If you're using the uv flow (recommended), it's already pinned in `pyproject.toml` — just remember the env var:

```bash
HF_HUB_ENABLE_HF_TRANSFER=1 uv run hf download ...
```

On a typical home connection you should see bursts of 50–80 MB/s once the chunked transfer warms up.

If you skipped the uv project and used the standalone `hf` installer instead, `pip install hf_transfer` fails on macOS with PEP 668 ("externally-managed environment"). Install into the hf installer's own venv instead:

```bash
~/.hf-cli/venv/bin/pip install -U hf_transfer
```

For private/gated repos, set `HF_TOKEN` (from https://huggingface.co/settings/tokens) or run `uv run hf auth login` once.

### pi install fails with `EACCES` or `EBADENGINE`
The installer is a thin wrapper around `npm install -g @earendil-works/pi-coding-agent`, so it needs a recent Node *and* a user-writable npm prefix. Two failure modes:

- **`EBADENGINE` warnings** about `undici` (needs Node ≥ 20.18.1) or `hosted-git-info` (^20.17.0 || ≥ 22.9.0) — your Node is too old.
- **`EACCES: permission denied, mkdir '/usr/local/lib/node_modules/...'`** — Node was installed from the official `.pkg`, which puts globals under root-owned `/usr/local`. Don't `sudo npm i -g`; it leaves root-owned caches that break `pi update` later.

Fix both at once by replacing the system Node with a user-owned one. Either:

```bash
# Option A — Homebrew
sudo rm -rf /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx \
            /usr/local/lib/node_modules /usr/local/include/node
brew install node
hash -r
npm install -g @earendil-works/pi-coding-agent
```

```bash
# Option B — nvm (no sudo at all)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
exec $SHELL -l
nvm install 22 && nvm use 22
npm install -g @earendil-works/pi-coding-agent
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

### Model writes `<function=bash>` instead of actually running tools
Tool-call format bug in the GGUF's embedded template. Run `fetch-template` and restart `qwen-serve`. See [Tool calling](#tool-calling).

### pi routes to a cloud provider instead of localhost
If `pi --model <X>` fails with `Error: No API key found for mistral` (or `openai`, `groq`, etc.) and the footer shows a built-in provider like `(mistral) <X>` next to your model name, the model `id` in your `models.json` is colliding with one of pi's built-in model entries. pi has its own registry of public model IDs (`mistral/devstral-small-2507`, `openai/gpt-oss-20b`, etc.) and resolves `--model X` against built-ins before custom providers.

Fix: rename the model `id` in `~/.pi/agent/models.json` to something unique — this repo prefixes locally-served alternates with `local-`, e.g. `local-devstral-small-2507`, `local-gpt-oss-20b`. The matching `-a` alias passed to `llama-server` (set via `ALIAS=` in the serve scripts) must change in lockstep, or `pi --list-models` will report a model id the server doesn't actually answer to.

Verify with `pi --list-models | grep local-llamacpp` — you should see your renamed ids only under the `local-llamacpp` provider.

### Out of memory at load
The default context is 131k, sized for a 64 GB Mac. On a 32 GB Mac, drop it: `CTX=32768 qwen-serve` (or `CTX=65536` if tight is OK). Failing that, drop the quant (Q5_K_M → Q4_K_M). You can also halve KV-cache memory with `--cache-type-k q8_0 --cache-type-v q8_0` — see [Choosing a quant](#choosing-a-quant).

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

## Recording the demo

The GIF at the top of this README is generated with [vhs](https://github.com/charmbracelet/vhs) — a scripted terminal recorder. The tape lives in [`demo/pi-qwen.tape`](demo/pi-qwen.tape), so re-running it after a change is one command instead of "perform the demo perfectly again."

### Prerequisites

```bash
brew install vhs ttyd ffmpeg
```

`vhs` drives the recording, `ttyd` is the PTY web bridge it talks to, `ffmpeg` does the encode. All three must be on PATH.

### How a recording works

vhs spawns a headless Chrome that connects to a `ttyd`-hosted shell. It executes the `.tape` script keystroke-by-keystroke, screenshots each frame, and renders to the file named in the `Output` directive. **vhs does not start `qwen-serve`** — start it in a separate terminal first, otherwise pi will fail to connect and the recording will end early with `context canceled`.

### Record

```bash
qwen-serve                              # terminal 1
vhs demo/pi-qwen.tape                   # terminal 2
```

Output lands at `demo/pi-qwen.gif`.

### Iterate

`vhs serve` opens a local WebSocket preview — the tape re-renders on save, so you can tune `Sleep` durations and styling without burning a full render each time:

```bash
vhs serve
# edit demo/pi-qwen.tape in your editor; preview updates on save
```

### What the directives do

| Directive | What it controls |
|---|---|
| `Output demo/pi-qwen.gif` | Output path. Swap to `.mp4` or `.webm` for smaller files. |
| `Set FontSize 14` | Render size of glyphs. |
| `Set Width 1400 / Height 800` | Canvas in px. Bigger = sharper but heavier. |
| `Set Theme "..."` | One of vhs's bundled themes. |
| `Set TypingSpeed 50ms` | Per-keystroke delay for `Type`. |
| `Set PlaybackSpeed 1.5` | Speeds up the final video; useful when decode is slow. |
| `Hide ... Show` | Run commands without recording (great for `cd` + `clear`). |
| `Type "..."` | Types a string. |
| `Enter` | Submits. |
| `Sleep 60s` | Waits — vhs has no "wait for output" primitive, so you size this empirically. |

### GIF vs MP4

A 60-second decode at 1400×800 produces an **8–20 MB GIF**, which is close to GitHub's README image limit. If it bloats, change one line:

```
Output demo/pi-qwen.mp4
```

and embed in the README with `<video src="demo/pi-qwen.mp4" controls></video>`. GitHub renders it inline at roughly 1/10th the size.

## Layout of this repo

```
pi_qwen/
├── README.md            # this file
├── LICENSE              # MIT
├── scripts/
│   ├── qwen-serve       # start llama-server for Qwen3-Coder-30B-A3B
│   ├── gptoss-serve     # alternate: OpenAI gpt-oss-20b
│   ├── devstral-serve   # alternate: Mistral Devstral-Small-2507
│   ├── serve-stop       # kill whatever llama-server is on port 8080
│   ├── qwen-test        # one-shot chat-completion smoke test
│   ├── tool-call-test   # model-agnostic check that pi-style tool_calls fire
│   └── fetch-template   # fetch Qwen's official chat template (fixes tool calls)
├── bench/
│   └── throughput.sh    # llama-bench wrapper for pp/tg tok/s
├── demo/
│   ├── pi-qwen.tape     # vhs script for the README demo
│   └── smoke.tape       # minimal vhs script to verify the toolchain
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

## Acknowledgments

This README was co-written by Claude Code and the Qwen3-Coder-30B-A3B model with Pi.
