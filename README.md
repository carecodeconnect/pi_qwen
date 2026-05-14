# pi_sandbox

A sandbox for running [pi](https://pi.dev) — a minimal terminal coding agent — against **local** models on Apple Silicon. Swap models, swap inference engines, A/B them on your own hardware. No API keys. No cloud round-trips. All inference on your machine.

The documented default is [Qwen3-Coder-30B-A3B-Instruct](https://huggingface.co/Qwen/Qwen3-Coder-30B-A3B-Instruct) via [llama.cpp](https://github.com/ggml-org/llama.cpp), with wired-up alternates for [gpt-oss-20b](https://huggingface.co/openai/gpt-oss-20b) and [GLM-4.5-Air](https://huggingface.co/zai-org/GLM-4.5-Air). The [model comparison](#model-comparison) section explains the trade-offs and [Tested and rejected](#tested-and-rejected) records what didn't work.

![pi + Qwen3-Coder demo](demo/pi-qwen.gif)

## Why this stack

- **Local models on Apple Silicon are practical now.** A modern MoE in Q5 quant (~12–20 GB) runs at 50–60 tok/s decode on an M1 Max with no cloud round-trip. Coding-agent latency is workable; cost is electricity.
- **pi is an OpenAI-API-compatible coding agent**, so it talks to a local inference server (llama.cpp, mistral.rs, vLLM, …) the same way it talks to any cloud provider. Drop-in by design.
- **llama.cpp** has the most mature Metal backend and ships precompiled via Homebrew — no Xcode required. The repo also has scaffolding to swap in [mistral.rs](#alternative-mistralrs-rust) as a Rust-native alternative.
- **Sandbox by intent.** The scripts and configs make it cheap to try a new model: download a GGUF, drop in a serve wrapper, add a `models.json` entry, run `tool-call-test`. The [Tested and rejected](#tested-and-rejected) section is what that workflow's failure cases look like in practice.

## Tested on

- Apple M1 Max, 64 GB RAM, macOS 26.3 (`arm64`)
- llama.cpp via Homebrew (`b9100`)
- pi `latest`
- Quant: `Qwen3-Coder-30B-A3B-Instruct-Q5_K_M.gguf` (~21 GB on disk, ~37 GB resident with the default 131k context)

Measured throughput on this hardware (M1 Max, llama.cpp `b9100`, `-fa 1 -ngl 99 -r 3`):

| test                | Qwen3-Coder-30B-A3B<br>(Q5_K_M, 20 GiB) | gpt-oss-20b<br>(MXFP4, 11 GiB) | GLM-4.5-Air<br>(UD-Q3_K_XL, 51 GiB) |
| ------------------- | --------------------------------------: | -----------------------------: | ----------------------------------: |
| pp512 (prefill)     |                          593.80 ± 4.38 |                **755.59 ± 0.90** |                       160.62 ± 1.25 |
| pp2048              |                          554.40 ± 0.51 |                **741.53 ± 1.33** |                       150.45 ± 1.76 |
| pp8192              |                          409.13 ± 7.86 |                **650.61 ± 7.65** |                       116.98 ± 0.47 |
| tg128 (decode)      |                           50.76 ± 0.21 |                 **59.67 ± 0.46** |                        20.57 ± 0.08 |
| tg512               |                           50.00 ± 0.11 |                 **60.40 ± 0.31** |                        19.82 ± 0.30 |
| pp8192+tg128        |                          356.51 ± 2.71 |                **544.15 ± 3.87** |                       104.77 ± 1.50 |

gpt-oss-20b is **~1.2–1.6× faster than Qwen** across the board; the gap widens at long contexts because gpt-oss has fewer total parameters (21 B vs 30 B) despite both being MoE. GLM-4.5-Air decodes **~2.5× slower than Qwen** and **~3× slower than gpt-oss** — expected given 12 B active params (4× Qwen's) and the model running near the wired-memory ceiling. Prefill is ~3.5–5× slower, large enough to feel in long-context agent turns. See [Benchmarking](#benchmarking) for the raw `llama-bench` output and how to reproduce.

Should work on any Apple Silicon Mac with ≥ 32 GB RAM. Bigger context windows or higher-bit quants need more.

### Model comparison

Three candidates work end-to-end with pi on this hardware:

- **Qwen3-Coder-30B-A3B-Instruct** (MoE, ~3 B active of 30 B, Q5_K_M, ~20 GiB) — **current default**. Coder-tuned weights, strong tool-call coherence, balanced speed and quality on real coding tasks. Upstream benchmarks: [Qwen3-Coder blog](https://qwenlm.github.io/blog/qwen3-coder/).
- **gpt-oss-20b** (MoE, ~3.6 B active of 21 B, MXFP4, ~11 GiB) — **competitive**. Clean tool calls, ~1.2–1.6× faster than Qwen on the same prompt sweep (see [Tested on](#tested-on)). Generalist-reasoning-tuned rather than coder-specialized; survey and Q&A feel just as good, dense codegen quality has not been fully evaluated. Upstream benchmarks: [OpenAI gpt-oss announcement](https://openai.com/index/introducing-gpt-oss/).
- **GLM-4.5-Air** (MoE, ~12 B active of 106 B, Unsloth UD-Q3_K_XL, ~51 GiB) — **marginal but works.** Agent-tuned, clean tool calls, decode ~20 tok/s (~2.5× slower than Qwen — see [Tested on](#tested-on)). Needs a Metal wired-memory cap bump (see [troubleshooting](#kiogpucommandbuffercallbackerroroutofmemory-during-inference)). Upstream benchmarks: [Z.ai GLM-4.5 blog](https://z.ai/blog/glm-4.5).

### Tested and rejected

Documenting what didn't work so the same paths don't get retried. Both kept this short subsection but removed from `config/models.json`, the serve scripts, and the disk; the GGUFs are not in the Quickstart path.

- **Devstral-Small-2507** (24 B **dense**, Unsloth UD-Q5_K_XL, ~17 GiB) — **failed: bandwidth + tool-call coherence.**
  - Decode ~5× slower than Qwen (~11 tok/s vs ~51 tok/s) — dense 24 B saturates Apple Silicon's unified-memory bandwidth.
  - Asked to enumerate the repo, Devstral emitted a runaway `find` whose `-name` clauses looped duplicates for hundreds of patterns before truncation.
  - **Lesson:** dense ≥ ~20 B is bandwidth-bound on M1 Max regardless of quant — stick to MoE with low active params.
- **DeepSeek-Coder-V2-Lite-Instruct** (16 B MoE, **2.4 B active**, Q5_K_M, ~12 GB) — **failed: model not trained for structured tool calls.**
  - Architecturally a perfect fit (smallest-active-params coder we evaluated); chat works fine.
  - But the upstream `chat_template` is 459 bytes total and renders only `user`/`assistant`/`system` roles with no `<tool_call>` envelope — the model was never trained to emit structured tool calls. Asked to call `get_weather`, it suggested *external* weather websites instead.
  - No template-fetch trick recovers this — the *model* doesn't speak tool calling.
  - **Lesson:** models released before ~mid-2024 (DeepSeek-Coder-V2, CodeLlama, StarCoder-2, Yi-Coder, …) generally predate the structured tool-call norm and are likely to fail the same way. Always run `tool-call-test` before trusting an older model.

### Next model trials

Candidates queued for testing on this same 64 GB M1 Max. All MoE (dense ≥24 B is ruled out by the Devstral result above) and known to have working structured tool calling in current llama.cpp.

- **[Qwen3-Coder-Next-80B-A3B-Instruct](https://huggingface.co/unsloth/Qwen3-Coder-Next-GGUF)** (MoE, **3 B active** of 80 B, **Q3_K_M, 38 GB**) — **in progress.** Scaled-up sibling of the Qwen3-Coder-30B default; same 3 B active params, same coder-tuning, same template trick. Wired up via [`qwennext-serve`](#qwennext-serve-alternate-model). Quant picked to land under the default 44 GB Metal cap so no `sysctl` prereq is needed (cleaner than GLM-Air's path). Note: Unsloth doesn't ship a `UD-Q3_K_XL` for this model — vanilla `Q3_K_M` was the closest in-budget option. Upstream benchmarks: [Qwen3-Coder blog](https://qwenlm.github.io/blog/qwen3-coder/).
- **[gpt-oss-120b](https://huggingface.co/openai/gpt-oss-120b)** (MoE, ~5.1 B active of 117 B, MXFP4 native, ~63 GB) — **cleanest scale-up of the gpt-oss-20b favorite.** Same chat template, same `--jinja`-only wiring, same sampler recipe. The catch: 63 GB weights on a 64 GB Mac leave ~1 GB headroom — forces `CTX` to 16–32 K and minimal background apps. Similar tightness to vanilla `Q3_K_M` GLM, which is why GLM dropped to UD-Q3_K_XL. Upstream benchmarks: [OpenAI gpt-oss announcement](https://openai.com/index/introducing-gpt-oss/).
- **[Llama 4 Scout](https://huggingface.co/meta-llama/Llama-4-Scout-17B-16E-Instruct)** (MoE, **17 B active** of 109 B, UD-Q3/Q4, ~50–60 GB) — **expected to underperform Qwen-Coder-Next.** 17 B active is much higher than ideal for Apple Silicon's bandwidth ceiling; decode will be slower than the 3 B-active alternatives despite a similar total-parameter count. Not agent-tuned the way GLM-Air is. Worth testing only to confirm the bandwidth-vs-active-params hypothesis empirically.

Skipped at this hardware tier: DeepSeek-V3/V3.1/V3.2 (~200 GB+ at Q2 — see [DeepSeek note](#a-note-on-deepseek-for-this-hardware) below), Kimi-K2/K2.6 (~350 GB at dynamic 2-bit), Qwen3-Coder-480B (~150 GB at Q3), MiniMax-M1, Mixtral 8x22B (39 B active = same bandwidth death as Devstral). All need a 128 GB+ Mac to be worth the disk space.

### A note on DeepSeek for this hardware

DeepSeek doesn't currently ship a model that's *both* coder-tuned, small enough for a 64 GB Mac, *and* trained for structured tool calls. The matrix as of May 2026:

- **DeepSeek-Coder-V2-Lite** (16 B/2.4 B active) — small enough, but no tool-call training (failed above).
- **DeepSeek-Coder-V2-Instruct** (236 B/21 B active) — tool calls work in V3+ post-training, but too big at any quant for 64 GB.
- **DeepSeek-V3 / V3.1 / V3.2-Exp** (671 B/37 B active) — strong tool calling, but ~200–250 GB at dynamic 2-bit; needs a 192 GB+ Mac.
- **DeepSeek-R1-Distill-Qwen-14B / 32B** — dense distillations into Qwen, would be the only DeepSeek-flavored option that fits, but: (a) dense 32 B is Devstral territory, (b) the distillations target *reasoning* not *coding* and are not trained for tool calls in the same shape pi expects.

Net: there is no DeepSeek model that satisfies all three constraints on a 64 GB Mac today. Qwen3-Coder and GLM-4.5-Air fill the slot DeepSeek would otherwise occupy.

## Python tooling (uv)

The only Python this repo needs is the `hf` CLI (from `huggingface_hub`) and `hf_transfer` for fast multi-stream downloads. Both live in a uv-managed venv pinned by `pyproject.toml` / `uv.lock` — no global `pip install`, no PEP 668 fights with system Python.

```bash
# One-time setup (run from inside this repo, wherever you cloned it)
curl -LsSf https://astral.sh/uv/install.sh | sh    # install uv if you don't have it
uv sync                                             # creates .venv/, installs deps from lockfile

# Run hf commands inside the project venv
uv run hf --version
HF_HUB_ENABLE_HF_TRANSFER=1 uv run hf download <repo> <file> --local-dir <dest>
```

If you'd rather have `hf` on PATH without prefixing `uv run` (handy for `cd`-ing into your model directory and running downloads from there), two options:
- `uv tool install huggingface_hub` — puts `hf` in `~/.local/bin` via uv's tool venv, available globally.
- Activate the project venv once per shell session: `source .venv/bin/activate` (from the repo root).

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

# 4. From inside the cloned repo, sync Python deps — gets you `hf`
#    (huggingface_hub CLI) and hf_transfer (multi-stream downloads),
#    pinned and reproducible. Then activate the venv so `hf` is on PATH.
uv sync
source .venv/bin/activate

# 5. Download the model (~21 GB). With the venv activated, `hf` works anywhere.
mkdir -p ~/models/qwen3-coder-30b-a3b && cd ~/models/qwen3-coder-30b-a3b
HF_HUB_ENABLE_HF_TRANSFER=1 hf download \
  unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF \
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
ALIAS=local-glm-4.5-air           tool-call-test   # against GLM-4.5-Air
```

If this fails, pi will not see tool calls from that model either — fix the chat-template wiring before running pi.

### `serve-stop`
Kills whatever llama-server is currently bound to port 8080 (override with `PORT=…`). Useful when switching between `qwen-serve` / `gptoss-serve` / `glmair-serve`, since only one server can hold the port at a time.

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
# Install once (assumes `hf` on PATH — see Python tooling)
mkdir -p ~/models/gpt-oss-20b
HF_HUB_ENABLE_HF_TRANSFER=1 hf download \
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

### `qwennext-serve` (alternate model)
Serves [`Qwen3-Coder-Next-80B-A3B-Instruct`](https://huggingface.co/Qwen/Qwen3-Next-80B-A3B-Instruct) — the scaled-up sibling of the Qwen3-Coder-30B-A3B default. 80 B total, **3 B active** (same as the 30B variant), 256 K native context. Picked `Q3_K_M` (~38 GB) to hit the "real headroom" target — fits under the default 44 GB Metal cap on a 64 GB Mac, so no `sysctl iogpu.wired_limit_mb` bump needed (unlike GLM-4.5-Air).

```bash
# Install once (assumes `hf` on PATH — see Python tooling)
mkdir -p ~/models/qwen3-coder-next
HF_HUB_ENABLE_HF_TRANSFER=1 hf download \
  unsloth/Qwen3-Coder-Next-GGUF Qwen3-Coder-Next-Q3_K_M.gguf \
  --local-dir ~/models/qwen3-coder-next
cp scripts/qwennext-serve ~/bin/ && chmod +x ~/bin/qwennext-serve

# Fetch the upstream chat template — same tool-call bug fix as Qwen3-Coder-30B
DEST_DIR=~/models/qwen3-coder-next/templates \
  DEST=$DEST_DIR/qwen3-next-official.jinja \
  TOKCONF_URL=https://huggingface.co/Qwen/Qwen3-Next-80B-A3B-Instruct/resolve/main/tokenizer_config.json \
  fetch-template

# Serve (stop other llama-server processes first)
qwennext-serve

# In pi
pi --model local-qwen3-coder-next
```

Defaults: `CTX=131072`, sampler temp 0.6 / top-p 0.95 / top-k 20 (Qwen's official recipe — same as Qwen3-Coder-30B), `--cache-type-k q8_0 --cache-type-v q8_0` baked in to keep KV cache compact at the larger size. Uses `--chat-template-file` pointed at the fetched upstream template (the Unsloth GGUF inherits Qwen3-Coder-30B's tool-call format bug — same fix applies).

### `glmair-serve` (alternate model)
Serves Z.ai's [`GLM-4.5-Air`](https://huggingface.co/zai-org/GLM-4.5-Air) ([GitHub](https://github.com/zai-org/GLM-4.5)) — a 106 B MoE (~12 B active) from the GLM-4.5 "ARC" family (Agentic, Reasoning, Coding), purpose-tuned for tool-using agents. Uses Unsloth's dynamic Q3 quant (UD-Q3_K_XL, ~55 GB across two shards) — the largest variant that fits on a 64 GB Apple Silicon Mac with KV-cache headroom.

```bash
# Install once (assumes `hf` on PATH — see Python tooling)
mkdir -p ~/models/glm-4.5-air
HF_HUB_ENABLE_HF_TRANSFER=1 hf download \
  unsloth/GLM-4.5-Air-GGUF --include "UD-Q3_K_XL/*" \
  --local-dir ~/models/glm-4.5-air
cp scripts/glmair-serve ~/bin/ && chmod +x ~/bin/glmair-serve

# Serve (stop other llama-server processes first)
glmair-serve

# In pi
pi --model local-glm-4.5-air
```

**Required first:** raise macOS's Metal wired-memory cap or inference will return HTTP 500 with `kIOGPUCommandBufferCallbackErrorOutOfMemory`. The 51 GiB weights exceed the default ~44 GB cap on a 64 GB Mac:

```bash
sudo sysctl iogpu.wired_limit_mb=57344   # 56 GB cap, leaves 8 GB for OS
```

Non-persistent (resets on reboot). See [troubleshooting](#kiogpucommandbuffercallbackerroroutofmemory-during-inference) for the persistent variant.

Defaults: `CTX=32768` (not 131k — KV budget is tight at this model size; q8_0 KV cache is on by default to halve memory), sampler temp 0.6 / top-p 0.95 (Z.ai's official GLM-4.5 recipe). Unsloth's GGUFs embed a corrected chat template that fixes the upstream tool-call format bug, so `--jinja` alone is enough — no `--chat-template-file` override needed (unlike Qwen3-Coder).

llama.cpp loads sharded GGUFs automatically when you point at the `-00001-of-00002` shard; the second shard must be in the same directory.

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
If `pi --model <X>` fails with `Error: No API key found for openai` (or `groq`, `mistral`, etc.) and the footer shows a built-in provider like `(openai) <X>` next to your model name, the model `id` in your `models.json` is colliding with one of pi's built-in model entries. pi has its own registry of public model IDs (`openai/gpt-oss-20b`, `mistral/devstral-small-2507`, etc.) and resolves `--model X` against built-ins before custom providers.

Fix: rename the model `id` in `~/.pi/agent/models.json` to something unique — this repo prefixes locally-served alternates with `local-`, e.g. `local-gpt-oss-20b`, `local-glm-4.5-air`. The matching `-a` alias passed to `llama-server` (set via `ALIAS=` in the serve scripts) must change in lockstep, or `pi --list-models` will report a model id the server doesn't actually answer to.

Verify with `pi --list-models | grep local-llamacpp` — you should see your renamed ids only under the `local-llamacpp` provider.

### Out of memory at load
The default context is 131k, sized for a 64 GB Mac. On a 32 GB Mac, drop it: `CTX=32768 qwen-serve` (or `CTX=65536` if tight is OK). Failing that, drop the quant (Q5_K_M → Q4_K_M). You can also halve KV-cache memory with `--cache-type-k q8_0 --cache-type-v q8_0` — see [Choosing a quant](#choosing-a-quant).

### `kIOGPUCommandBufferCallbackErrorOutOfMemory` during inference
Different failure mode from the load-time OOM above. The model loads fine, then the first `chat/completions` request returns HTTP 500 and the server log shows:

```
error: Insufficient Memory (00000008:kIOGPUCommandBufferCallbackErrorOutOfMemory)
```

This happens when the GGUF is large enough (≥ ~45 GB) that the *weights themselves* exceed macOS's default Metal wired-memory cap. On a 64 GB Mac that cap is ~44 GB (≈ 67% of total RAM) — anything above it can't be allocated to the GPU and inference fails the first time Metal touches an unwired page. The KV-cache compression knob from the previous tip doesn't help here, because the problem is the weights, not the KV cache. Hit while serving `GLM-4.5-Air-UD-Q3_K_XL` (~55 GB) and `gpt-oss-120b` (~63 GB).

Raise the cap with `sysctl`:

```bash
sudo sysctl iogpu.wired_limit_mb=57344    # 56 GB — leaves 8 GB for OS/apps on a 64 GB Mac
```

Safe upper bound is `total_RAM_MB - 8192` (leave 8 GB for the OS). The change is non-persistent — to make it survive reboot, add a `/Library/LaunchDaemons/com.local.iogpu-limit.plist` running the same `sysctl` at boot, or add the line to `/etc/sysctl.conf` (depending on macOS version).

Verify with:

```bash
sysctl iogpu.wired_limit_mb
```

Setting it back to `0` restores the macOS default.

## Alternative inference engines (Rust)

llama.cpp is the default in this repo because its Metal backend is mature, Homebrew ships precompiled binaries, and the GGUF + jinja-template path is well-trodden for tool calling. But pi only cares about the OpenAI-compatible HTTP shape — any server that speaks `/v1/chat/completions` and emits structured `tool_calls` is a drop-in replacement. A few Rust-native engines worth A/B-ing on this hardware:

### mistral.rs (primary alternate)

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

### Other Rust engines worth tracking

Neither is the default path yet — each is here as a candidate to benchmark against mistral.rs once the llama.cpp baseline is solid.

- **[candle-vllm](https://github.com/EricLBuehler/candle-vllm)** — same author as mistral.rs. Aims to bring vLLM-style continuous batching to Candle, with an OpenAI-compatible server. Less mature than mistral.rs; worth tracking but not first.
- **[Crane](https://github.com/lucasjinreal/Crane)** — Candle-based, OpenAI-compatible via `crane-oai`. Claims ~6× M-series speedup vs llama.cpp; newer, less battle-tested. Worth a benchmark but I wouldn't rely on it for daily use yet.

Both build with `cargo install` and the same Xcode/Metal requirement as mistral.rs. To wire either into pi, point a new entry in `~/.pi/agent/models.json` at the engine's port and use whatever id it advertises at `/v1/models`.

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

Real runs on Apple M1 Max, 64 GB, llama.cpp build `2e97c5f96 (9100)`:

**Qwen3-Coder-30B-A3B (Q5_K_M, 20.23 GiB, 30.53 B params, 3 B active)**
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

**gpt-oss-20b (MXFP4, 11.27 GiB, 20.91 B params, ~3.6 B active)**
```
| model                 |      size |  params | backend  | threads | fa |          test |             t/s |
| --------------------- | --------: | ------: | -------- | ------: | -: | ------------: | --------------: |
| gpt-oss 20B MXFP4 MoE | 11.27 GiB | 20.91 B | BLAS,MTL |       8 |  1 |         pp512 |   755.59 ± 0.90 |
| gpt-oss 20B MXFP4 MoE | 11.27 GiB | 20.91 B | BLAS,MTL |       8 |  1 |        pp2048 |   741.53 ± 1.33 |
| gpt-oss 20B MXFP4 MoE | 11.27 GiB | 20.91 B | BLAS,MTL |       8 |  1 |        pp8192 |   650.61 ± 7.65 |
| gpt-oss 20B MXFP4 MoE | 11.27 GiB | 20.91 B | BLAS,MTL |       8 |  1 |         tg128 |    59.67 ± 0.46 |
| gpt-oss 20B MXFP4 MoE | 11.27 GiB | 20.91 B | BLAS,MTL |       8 |  1 |         tg512 |    60.40 ± 0.31 |
| gpt-oss 20B MXFP4 MoE | 11.27 GiB | 20.91 B | BLAS,MTL |       8 |  1 |  pp8192+tg128 |   544.15 ± 3.87 |
```

**GLM-4.5-Air (Unsloth UD-Q3_K_XL, 51.01 GiB, 110.47 B params, 12 B active)**
```
| model                           |      size |   params | backend  | threads | fa |          test |             t/s |
| ------------------------------- | --------: | -------: | -------- | ------: | -: | ------------: | --------------: |
| glm4moe 106B.A12B Q3_K - Medium | 51.01 GiB | 110.47 B | BLAS,MTL |       8 |  1 |         pp512 |   160.62 ± 1.25 |
| glm4moe 106B.A12B Q3_K - Medium | 51.01 GiB | 110.47 B | BLAS,MTL |       8 |  1 |        pp2048 |   150.45 ± 1.76 |
| glm4moe 106B.A12B Q3_K - Medium | 51.01 GiB | 110.47 B | BLAS,MTL |       8 |  1 |        pp8192 |   116.98 ± 0.47 |
| glm4moe 106B.A12B Q3_K - Medium | 51.01 GiB | 110.47 B | BLAS,MTL |       8 |  1 |         tg128 |    20.57 ± 0.08 |
| glm4moe 106B.A12B Q3_K - Medium | 51.01 GiB | 110.47 B | BLAS,MTL |       8 |  1 |         tg512 |    19.82 ± 0.30 |
| glm4moe 106B.A12B Q3_K - Medium | 51.01 GiB | 110.47 B | BLAS,MTL |       8 |  1 |  pp8192+tg128 |   104.77 ± 1.50 |
```

Reading the numbers:
- **Prefill scaling.** All three models slow down with longer prompts (Qwen 594→409, gpt-oss 756→651, GLM 161→117 from pp512 to pp8192). The drop is gentler on gpt-oss — fewer total parameters means less compute per token at prefill time.
- **Decode is steady within a model** (`tg128` ≈ `tg512`). It's bandwidth-bound, not compute-bound, so generation length barely matters.
- **gpt-oss is ~1.2–1.6× faster than Qwen across the sweep**, with the gap widest at `pp8192+tg128` — the agent-realistic combined run.
- **GLM-4.5-Air is ~3–4× slower than Qwen and ~5–6× slower than gpt-oss.** Two effects compound: 12 B active params (4× Qwen's 3 B) means more compute per token, and the 51 GiB weights run right against the 56 GB Metal wired-memory cap, so any page miss is expensive. The architectural prediction (decode slowdown ≈ active-param ratio) holds: 50.8 / 20.6 ≈ 2.5×, matched closely. Coding-agent usable at ~20 tok/s decode, but you feel the long-context prefill.
- **MoE throughput moves with quant, batch size, context length, and what else is on the GPU.** Reproduce all runs on your own hardware before reading too much into the deltas.

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
pi_sandbox/
├── README.md            # this file
├── LICENSE              # MIT
├── scripts/
│   ├── qwen-serve       # start llama-server for Qwen3-Coder-30B-A3B
│   ├── qwennext-serve   # alternate: Qwen3-Coder-Next-80B-A3B (3B active)
│   ├── gptoss-serve     # alternate: OpenAI gpt-oss-20b
│   ├── glmair-serve     # alternate: Z.ai GLM-4.5-Air (106B MoE)
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
