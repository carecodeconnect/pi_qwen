# Troubleshooting

## Download is glacial (single-digit MB/s)

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

## pi install fails with `EACCES` or `EBADENGINE`

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

Alternatively, install pi extensions project-locally with `pi install -l <source>` — see [docs/04-tool-calling.md](./04-tool-calling.md#extending-pi-with-custom-tools). That avoids the global-install permission issue entirely.

## `error: unknown value for --flash-attn`

Newer llama.cpp requires `-fa on` (or `off`/`auto`), not bare `-fa`. The scripts in this repo already use the new form.

## pi doesn't see the model

```bash
pi --list-models
jq . ~/.pi/agent/models.json   # validate JSON
curl -s http://127.0.0.1:8080/v1/models | jq   # confirm server is up
```

The model `id` in `models.json` must match the `-a` alias passed to `llama-server`.

## Garbled or template-broken output

You probably forgot `--jinja`. Without it llama.cpp falls back to a generic template and Qwen3's chat tokens get mangled.

## Model writes `<function=bash>` instead of actually running tools

Tool-call format bug in the GGUF's embedded template. Run `fetch-template` and restart `qwen-serve`. See [docs/04-tool-calling.md](./04-tool-calling.md).

## pi routes to a cloud provider instead of localhost

If `pi --model <X>` fails with `Error: No API key found for openai` (or `groq`, `mistral`, etc.) and the footer shows a built-in provider like `(openai) <X>` next to your model name, the model `id` in your `models.json` is colliding with one of pi's built-in model entries. pi has its own registry of public model IDs (`openai/gpt-oss-20b`, `mistral/devstral-small-2507`, etc.) and resolves `--model X` against built-ins before custom providers.

Fix: rename the model `id` in `~/.pi/agent/models.json` to something unique — this repo prefixes locally-served alternates with `local-`, e.g. `local-gpt-oss-20b`, `local-glm-4.5-air`. The matching `-a` alias passed to `llama-server` (set via `ALIAS=` in the serve scripts) must change in lockstep, or `pi --list-models` will report a model id the server doesn't actually answer to.

Verify with `pi --list-models | grep local-llamacpp` — you should see your renamed ids only under the `local-llamacpp` provider.

## Out of memory at load

The default context is 131 k, sized for a 64 GB Mac. On a 32 GB Mac, drop it: `CTX=32768 qwen-serve` (or `CTX=65536` if tight is OK). Failing that, drop the quant (Q5_K_M → Q4_K_M). You can also halve KV-cache memory with `--cache-type-k q8_0 --cache-type-v q8_0` — see [docs/02-models.md → Choosing a quant](./02-models.md#choosing-a-quant).

## `kIOGPUCommandBufferCallbackErrorOutOfMemory` during inference

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
