# Quickstart

Get pi running against a local Qwen3-Coder model on Apple Silicon in ~10 minutes. Other models (`gpt-oss-20b`, `qwen3-coder-next`, `glm-4.5-air`) follow the same pattern — see [docs/03-serving.md](./03-serving.md).

## Prerequisites

- Apple Silicon Mac (M1+) with ≥ 32 GB RAM (64 GB recommended; see [docs/02-models.md](./02-models.md) for quant trade-offs)
- macOS 14+ for Metal 3 features
- Homebrew installed
- Node ≥ 20.18.1 (for pi — if you don't have it, see [docs/06-troubleshooting.md](./06-troubleshooting.md#pi-install-fails-with-eacces-or-ebadengine))

## End-to-end install

```bash
# 1. Install llama.cpp (Metal-enabled, precompiled)
brew install llama.cpp

# 2. Install pi
curl -fsSL https://pi.dev/install.sh | sh

# 3. Install uv (Python project/dependency manager)
curl -LsSf https://astral.sh/uv/install.sh | sh

# 4. From inside the cloned repo, sync Python deps — pins `hf` + `hf_transfer`
uv sync
source .venv/bin/activate

# 5. Download the model (~21 GB)
mkdir -p ~/models/qwen3-coder-30b-a3b && cd ~/models/qwen3-coder-30b-a3b
HF_HUB_ENABLE_HF_TRANSFER=1 hf download \
  unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF \
  Qwen3-Coder-30B-A3B-Instruct-Q5_K_M.gguf --local-dir .

# 6. Install the helper scripts to ~/bin
mkdir -p ~/bin
cp scripts/qwen-serve scripts/qwen-test scripts/fetch-template ~/bin/
chmod +x ~/bin/qwen-serve ~/bin/qwen-test ~/bin/fetch-template
# Make sure ~/bin is on PATH:
# echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc

# 7. Install the pi provider config
mkdir -p ~/.pi/agent
cp config/models.json ~/.pi/agent/models.json

# 8. Fetch Qwen's official chat template (needed for tool calling — see docs/04-tool-calling.md)
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

Once everything's installed, the day-to-day cycle is two commands in two terminals:

```bash
# Terminal 1 — start the server (leave it running)
qwen-serve

# Terminal 2 — drop into pi
cd /path/to/your/project
pi --model qwen3-coder-30b-a3b
```

Exit pi with `/exit` or Ctrl-D. The server keeps running across pi sessions; stop it with Ctrl-C or `serve-stop`.

To switch between models, `serve-stop` then start a different `*-serve` script. Only one llama-server can hold port 8080 at a time.

## Python tooling (uv)

The only Python this repo needs is the `hf` CLI (from `huggingface_hub`) and `hf_transfer` for fast multi-stream downloads. Both live in a uv-managed venv pinned by `pyproject.toml` / `uv.lock` — no global `pip install`, no PEP 668 fights with system Python.

```bash
# One-time setup (run from inside this repo)
curl -LsSf https://astral.sh/uv/install.sh | sh    # install uv if you don't have it
uv sync                                             # creates .venv/, installs deps from lockfile

# Run hf commands inside the project venv
uv run hf --version
HF_HUB_ENABLE_HF_TRANSFER=1 uv run hf download <repo> <file> --local-dir <dest>
```

If you'd rather have `hf` on PATH without prefixing `uv run`:
- `uv tool install huggingface_hub` — puts `hf` in `~/.local/bin` via uv's tool venv, available globally.
- Activate the project venv once per shell session: `source .venv/bin/activate` (from the repo root).

## Hugging Face authentication

Public GGUFs don't strictly need a token, but logging in lifts anonymous rate limits and is the path of least resistance if you ever pull a gated model.

1. **Create a token** at https://huggingface.co/settings/tokens. A *Read* token is enough for downloads.
2. **Log in once** — `huggingface_hub` stores the token in `~/.cache/huggingface/token`:
   ```bash
   uv run hf auth login           # paste the token when prompted
   uv run hf auth whoami          # verify
   ```

Alternatively, export `HF_TOKEN` in your shell rc — useful in scripted/CI contexts:

```bash
export HF_TOKEN=hf_xxxxxxxxxxxx
```

See the [HF CLI docs](https://huggingface.co/docs/huggingface_hub/en/guides/cli) for full coverage.
