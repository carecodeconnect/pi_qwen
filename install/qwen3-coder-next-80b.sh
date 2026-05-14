#!/usr/bin/env bash
# Install Qwen3-Coder-Next-80B-A3B-Instruct (long-context coder, ~38 GB GGUF).
# Idempotent — re-runs are safe.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODEL_DIR="$HOME/models/qwen3-coder-next"
GGUF_NAME="Qwen3-Coder-Next-Q3_K_M.gguf"
HF_REPO="unsloth/Qwen3-Coder-Next-GGUF"
TEMPLATE_DIR="$MODEL_DIR/templates"
TEMPLATE_PATH="$TEMPLATE_DIR/qwen3-next-official.jinja"
TOKCONF_URL="https://huggingface.co/Qwen/Qwen3-Next-80B-A3B-Instruct/resolve/main/tokenizer_config.json"

mkdir -p "$MODEL_DIR"

# 1. Download GGUF if missing
if [[ -f "$MODEL_DIR/$GGUF_NAME" ]]; then
  echo "model present: $MODEL_DIR/$GGUF_NAME ($(du -h "$MODEL_DIR/$GGUF_NAME" | cut -f1))"
else
  echo "downloading $GGUF_NAME (~38 GB) — this can take 30-60 min depending on bandwidth"
  HF_HUB_ENABLE_HF_TRANSFER=1 uv --directory "$REPO_ROOT" run hf download \
    "$HF_REPO" "$GGUF_NAME" --local-dir "$MODEL_DIR"
fi

# 2. Install serve script
mkdir -p "$HOME/bin"
cp "$REPO_ROOT/scripts/qwennext-serve" "$HOME/bin/qwennext-serve" && chmod +x "$HOME/bin/qwennext-serve"
echo "installed: $HOME/bin/qwennext-serve"

# 3. Fetch upstream chat template (same tool-call bug fix as Qwen3-Coder-30B)
DEST_DIR="$TEMPLATE_DIR" DEST="$TEMPLATE_PATH" TOKCONF_URL="$TOKCONF_URL" \
  "$REPO_ROOT/scripts/fetch-template"

# 4. Validate
echo
echo "qwen3-coder-next-80b install complete."
echo "Test with:"
echo "  qwennext-serve                          # terminal 1"
echo "  ALIAS=local-qwen3-coder-next tool-call-test   # terminal 2"
echo "  pi --model local-qwen3-coder-next       # terminal 2"
