#!/usr/bin/env bash
# Install Qwen3-Coder-30B-A3B-Instruct (default coder model, ~21 GB GGUF).
# Idempotent — re-runs are safe; downloads only what's missing.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODEL_DIR="$HOME/models/qwen3-coder-30b-a3b"
GGUF_NAME="Qwen3-Coder-30B-A3B-Instruct-Q5_K_M.gguf"
HF_REPO="unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF"

mkdir -p "$MODEL_DIR"

# 1. Download GGUF if missing
if [[ -f "$MODEL_DIR/$GGUF_NAME" ]]; then
  echo "model present: $MODEL_DIR/$GGUF_NAME ($(du -h "$MODEL_DIR/$GGUF_NAME" | cut -f1))"
else
  echo "downloading $GGUF_NAME (~21 GB) — this takes a few minutes on a fast connection"
  HF_HUB_ENABLE_HF_TRANSFER=1 uv --directory "$REPO_ROOT" run hf download \
    "$HF_REPO" "$GGUF_NAME" --local-dir "$MODEL_DIR"
fi

# 2. Install serve script
mkdir -p "$HOME/bin"
cp "$REPO_ROOT/scripts/qwen-serve" "$HOME/bin/qwen-serve" && chmod +x "$HOME/bin/qwen-serve"
echo "installed: $HOME/bin/qwen-serve"

# 3. Fetch the corrected chat template — fixes the tool-call bug in the
# Unsloth GGUF's embedded template. See docs/04-tool-calling.md
"$REPO_ROOT/scripts/fetch-template"

# 4. Validate
echo
echo "qwen3-coder-30b install complete."
echo "Test with:"
echo "  qwen-serve                     # terminal 1"
echo "  qwen-test 'reply with hello'   # terminal 2 — sanity check"
echo "  tool-call-test                 # terminal 2 — structured tool_calls"
echo "  pi --model qwen3-coder-30b-a3b # terminal 2 — actually use it"
