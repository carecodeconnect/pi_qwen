#!/usr/bin/env bash
# Base install: copies helper scripts to ~/bin and the pi provider config
# to ~/.pi/agent/. Idempotent — safe to re-run.
#
# Run once per machine before any of the model-specific install scripts.
# Assumes llama.cpp, pi, and uv are already installed (see docs/01-quickstart.md).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 1. ~/bin scripts
mkdir -p "$HOME/bin"
for s in qwen-test tool-call-test serve-stop fetch-template; do
  src="$REPO_ROOT/scripts/$s"
  dst="$HOME/bin/$s"
  if [[ ! -f "$src" ]]; then
    echo "error: $src missing — is REPO_ROOT correct?" >&2
    exit 1
  fi
  cp "$src" "$dst" && chmod +x "$dst"
  echo "installed: $dst"
done

# 2. pi provider config
mkdir -p "$HOME/.pi/agent"
cp "$REPO_ROOT/config/models.json" "$HOME/.pi/agent/models.json"
echo "installed: $HOME/.pi/agent/models.json"

# 3. Sanity check
if ! command -v llama-server >/dev/null; then
  case "$(uname -s)" in
    Darwin)
      echo "warning: llama-server not on PATH — install with: brew install llama.cpp" >&2 ;;
    Linux)
      echo "warning: llama-server not on PATH" >&2
      echo "         Debian trixie+/Ubuntu 26.04+:  sudo apt install llama.cpp" >&2
      echo "         Other distros:                 build from source (https://github.com/ggml-org/llama.cpp)" >&2 ;;
    *)
      echo "warning: llama-server not on PATH — see https://github.com/ggml-org/llama.cpp" >&2 ;;
  esac
fi
if ! command -v hf >/dev/null && ! [[ -f "$REPO_ROOT/.venv/bin/hf" ]]; then
  echo "warning: hf CLI not found — run 'uv sync' from $REPO_ROOT first" >&2
fi
if ! command -v pi >/dev/null; then
  echo "warning: pi not on PATH — install with: curl -fsSL https://pi.dev/install.sh | sh" >&2
fi

# 4. PATH check
case ":$PATH:" in
  *":$HOME/bin:"*) ;;
  *) echo "warning: $HOME/bin is not on PATH — add it to your shell rc:" >&2
     echo "  echo 'export PATH=\"\$HOME/bin:\$PATH\"' >> ~/.zshrc && source ~/.zshrc" >&2 ;;
esac

echo
echo "base install complete. Next: pick a model from install/ and run it."
echo "  install/qwen3-coder-30b.sh        # default coder model, ~21 GB  [Apple Silicon]"
echo "  install/qwen3-coder-next-80b.sh   # long-context coder, ~38 GB   [Apple Silicon]"
echo "  install/gpt-oss-20b.sh            # fastest, generalist, ~12 GB  [Apple Silicon]"
echo "  install/glm-4.5-air.sh            # largest, agent-tuned, ~55 GB [Apple Silicon]"
echo "  install/qwen-coder-3b.sh          # smallest coder, ~2 GB        [Linux/CPU, completion only]"
echo "  install/qwen3-4b.sh               # X270/CPU agent default, ~2.5 GB [Linux/CPU, pi tool-calling]"
