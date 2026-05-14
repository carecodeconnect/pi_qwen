# Serving

The helper scripts in `scripts/`. Each `*-serve` script wraps `llama-server` with the right flags for one model; `qwen-test`, `tool-call-test`, `serve-stop`, and `fetch-template` are model-agnostic utilities.

All serve scripts honor `MODEL=`, `HOST=`, `PORT=`, `CTX=`, and `ALIAS=` env-var overrides.

## `qwen-serve` (default — Qwen3-Coder-30B-A3B)

Starts `llama-server` with the flag set this repo has settled on.

```bash
qwen-serve                                  # defaults (131k context)
PORT=8081 CTX=65536 qwen-serve              # smaller context, different port
CTX=262144 qwen-serve                       # push it — uses ~24 GB KV cache
MODEL=~/models/other.gguf qwen-serve        # swap the model file
ALIAS=my-model qwen-serve                   # change the model id pi sees
```

Key flags it sets:

- `-ngl 99` — offload all layers to Metal GPU. Free on Apple Silicon since memory is unified.
- `-c 131072` — 131 k context. Sized for a 64 GB Apple Silicon Mac; drop to 32768/65536 on 32 GB machines, or bump to 262144 if you have the headroom.
- `-fa on` — flash attention (new llama.cpp requires explicit `on`/`off`/`auto`).
- `--jinja` — render the chat template.
- `--chat-template-file <path>` — load Qwen's official chat template instead of the GGUF-embedded one. See [docs/04-tool-calling.md](./04-tool-calling.md) for why.
- `--temp 0.6 --top-p 0.95 --top-k 20` — Qwen's official sampler recommendations.

## `qwennext-serve` (Qwen3-Coder-Next-80B-A3B)

Serves [`Qwen3-Coder-Next-80B-A3B-Instruct`](https://huggingface.co/Qwen/Qwen3-Next-80B-A3B-Instruct) — the scaled-up sibling of the 30B default. 80 B total, **3 B active** (same as the 30B), 256 K native context. Quant `Q3_K_M` (~38 GB) fits under the default 44 GB Metal cap so no `sysctl` bump needed.

```bash
# Install once
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

Defaults: `CTX=131072`, sampler temp 0.6 / top-p 0.95 / top-k 20 (Qwen's official, same as 30B), `--cache-type-k q8_0 --cache-type-v q8_0` baked in for KV-cache compactness. Uses `--chat-template-file` pointed at the fetched upstream template (the Unsloth GGUF inherits the 30B's tool-call format bug — same fix applies).

## `gptoss-serve` (gpt-oss-20b)

Serves OpenAI's [`gpt-oss-20b`](https://huggingface.co/openai/gpt-oss-20b) — 21 B MoE (~3.6 B active) with reasoning and built-in tool calling. MXFP4 native (~12 GB), no chat-template override needed.

```bash
# Install once
mkdir -p ~/models/gpt-oss-20b
HF_HUB_ENABLE_HF_TRANSFER=1 hf download \
  ggml-org/gpt-oss-20b-GGUF gpt-oss-20b-mxfp4.gguf \
  --local-dir ~/models/gpt-oss-20b
cp scripts/gptoss-serve ~/bin/ && chmod +x ~/bin/gptoss-serve

# Serve
gptoss-serve

# In pi
pi --model local-gpt-oss-20b
```

Defaults: `CTX=131072`, sampler temp 1.0 / top-p 1.0 (gpt-oss is reasoning-tuned and recommends near-deterministic sampling controlled by `reasoning_effort` in the system prompt rather than temperature).

The `local-` prefix on the model id avoids a collision with pi's built-in `gpt-oss-20b` entries (which route to OpenAI / Fireworks / Cloudflare / Bedrock). See [troubleshooting → pi routes to a cloud provider](./06-troubleshooting.md#pi-routes-to-a-cloud-provider-instead-of-localhost).

## `glmair-serve` (GLM-4.5-Air)

Serves Z.ai's [`GLM-4.5-Air`](https://huggingface.co/zai-org/GLM-4.5-Air) ([GitHub](https://github.com/zai-org/GLM-4.5)) — 106 B MoE (~12 B active) from the GLM-4.5 "ARC" family. Unsloth's UD-Q3_K_XL (~55 GB, two shards) is the largest variant that fits on a 64 GB Mac.

```bash
# Install once
mkdir -p ~/models/glm-4.5-air
HF_HUB_ENABLE_HF_TRANSFER=1 hf download \
  unsloth/GLM-4.5-Air-GGUF --include "UD-Q3_K_XL/*" \
  --local-dir ~/models/glm-4.5-air
cp scripts/glmair-serve ~/bin/ && chmod +x ~/bin/glmair-serve

# Serve
glmair-serve

# In pi
pi --model local-glm-4.5-air
```

**Required first:** raise macOS's Metal wired-memory cap or inference will return HTTP 500 with `kIOGPUCommandBufferCallbackErrorOutOfMemory`:

```bash
sudo sysctl iogpu.wired_limit_mb=57344   # 56 GB cap, leaves 8 GB for OS
```

Non-persistent (resets on reboot). See [troubleshooting](./06-troubleshooting.md#kiogpucommandbuffercallbackerroroutofmemory-during-inference) for the persistent variant.

Defaults: `CTX=32768` (not 131 k — KV budget is tight at this size; q8_0 KV cache on by default), sampler temp 0.6 / top-p 0.95 (Z.ai's GLM-4.5 recipe). Unsloth's GGUFs embed a corrected chat template, so `--jinja` alone is enough — no `--chat-template-file` override needed.

llama.cpp loads sharded GGUFs automatically when you point at `-00001-of-00002`; the second shard must be in the same directory.

## `qwen-test`

Single-shot prompt against the running server. Useful for sanity checks.

```bash
qwen-test                                        # default: "reply with just: hello"
qwen-test "what is 2+2"                          # custom prompt
ALIAS=local-gpt-oss-20b qwen-test "ping"         # works against any alias
```

## `tool-call-test`

Model-agnostic check that the running server returns structured `tool_calls`. Defines a `get_weather` tool and prompts the model to call it; passes only if `choices[0].message.tool_calls` is present.

```bash
ALIAS=qwen3-coder-30b-a3b         tool-call-test
ALIAS=local-gpt-oss-20b           tool-call-test
ALIAS=local-glm-4.5-air           tool-call-test
ALIAS=local-qwen3-coder-next      tool-call-test
```

If this fails, pi will not see tool calls from that model either — fix the chat-template wiring before running pi.

## `serve-stop`

Kills whatever llama-server is currently bound to port 8080 (override with `PORT=…`). Useful when switching between `qwen-serve` / `qwennext-serve` / `gptoss-serve` / `glmair-serve` — only one can hold the port at a time.

```bash
serve-stop                       # frees port 8080
PORT=8081 serve-stop             # different port
```

## `fetch-template`

Downloads Qwen's official chat template from Hugging Face. Run once after install for any model whose Unsloth GGUF has the tool-call template bug.

```bash
fetch-template                                              # defaults to Qwen3-Coder-30B
DEST=~/other/place/template.jinja fetch-template            # custom location
DEST_DIR=~/models/qwen3-coder-next/templates \
  DEST=$DEST_DIR/qwen3-next-official.jinja \
  TOKCONF_URL=https://huggingface.co/Qwen/Qwen3-Next-80B-A3B-Instruct/resolve/main/tokenizer_config.json \
  fetch-template                                            # for Qwen3-Coder-Next
```

See [docs/04-tool-calling.md](./04-tool-calling.md) for why this is needed.

## Running multiple models concurrently

Only one llama-server can hold port 8080. To run two simultaneously, use the `PORT=` override and add a second provider in `~/.pi/agent/models.json`:

```bash
PORT=8080 qwen-serve         # qwen3-coder-30b-a3b on :8080
PORT=8081 gptoss-serve       # local-gpt-oss-20b on :8081
```

Reality check on 64 GB:

| Combo | Weight footprint | Verdict |
|---|---:|---|
| Qwen-30B + gpt-oss-20b | ~31 GB | ✓ comfortable |
| Qwen-Next + gpt-oss-20b | ~47 GB | ⚠ tight, drop CTX |
| Anything + GLM-Air | ≥62 GB | ✗ don't |
| All three Qwen/gpt-oss | ~67 GB | ✗ won't fit |

Switching one-at-a-time with `serve-stop` takes <1 min and gives each model the full memory budget. That's almost always the right move on this hardware.
