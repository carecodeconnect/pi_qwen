#!/usr/bin/env bash
# Install Qwen3-Instruct-2507 4B (~2.5 GB Q4_K_M).
# Recommended X270/CPU default for pi agent loops — see docs/TODO_x270.md.
# Idempotent — re-runs are safe.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODEL_DIR="$HOME/models/qwen3-4b-instruct-2507"
GGUF_NAME="Qwen3-4B-Instruct-2507-Q4_K_M.gguf"
HF_REPO="unsloth/Qwen3-4B-Instruct-2507-GGUF"

mkdir -p "$MODEL_DIR"

# 1. Download GGUF if missing
if [[ -f "$MODEL_DIR/$GGUF_NAME" ]]; then
  echo "model present: $MODEL_DIR/$GGUF_NAME ($(du -h "$MODEL_DIR/$GGUF_NAME" | cut -f1))"
else
  echo "downloading $GGUF_NAME (~2.5 GB)"
  HF_HUB_ENABLE_HF_TRANSFER=1 uv --directory "$REPO_ROOT" run hf download \
    "$HF_REPO" "$GGUF_NAME" --local-dir "$MODEL_DIR"
fi

# 2. Install serve script
mkdir -p "$HOME/bin"
cp "$REPO_ROOT/scripts/qwen3-4b-serve" "$HOME/bin/qwen3-4b-serve" \
  && chmod +x "$HOME/bin/qwen3-4b-serve"
echo "installed: $HOME/bin/qwen3-4b-serve"

# 3. Fetch the official chat template (from Qwen's base repo, not the Unsloth
#    GGUF). Same rationale as install/qwen-coder-3b.sh: embedded templates emit
#    tool calls in formats llama-server can't parse into structured tool_calls.
TEMPLATE_DEST_DIR="$MODEL_DIR/templates"
TEMPLATE_DEST="$TEMPLATE_DEST_DIR/qwen3-4b-official.jinja"
if [[ -f "$TEMPLATE_DEST" ]]; then
  echo "template present: $TEMPLATE_DEST"
else
  echo "fetching official chat template"
  DEST_DIR="$TEMPLATE_DEST_DIR" \
    DEST="$TEMPLATE_DEST" \
    TOKCONF_URL="https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507/resolve/main/tokenizer_config.json" \
    "$REPO_ROOT/scripts/fetch-template"
fi

# 4. Validate
echo
echo "qwen3-4b install complete."
echo "Test with:"
echo "  qwen3-4b-serve                                       # terminal 1"
echo "  ALIAS=local-qwen3-4b-instruct-2507 tool-call-test    # terminal 2"
echo "  pi --model local-qwen3-4b-instruct-2507              # terminal 2"
