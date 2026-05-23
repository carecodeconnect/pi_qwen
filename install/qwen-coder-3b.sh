#!/usr/bin/env bash
# Install Qwen2.5-Coder-3B-Instruct (~2 GB Q4_K_M).
# Primary model for the Linux/CPU path (X270-class) — see docs/TODO_x270.md.
# Idempotent — re-runs are safe.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODEL_DIR="$HOME/models/qwen2.5-coder-3b"
GGUF_NAME="qwen2.5-coder-3b-instruct-q4_k_m.gguf"
HF_REPO="Qwen/Qwen2.5-Coder-3B-Instruct-GGUF"

mkdir -p "$MODEL_DIR"

# 1. Download GGUF if missing
if [[ -f "$MODEL_DIR/$GGUF_NAME" ]]; then
  echo "model present: $MODEL_DIR/$GGUF_NAME ($(du -h "$MODEL_DIR/$GGUF_NAME" | cut -f1))"
else
  echo "downloading $GGUF_NAME (~2 GB)"
  HF_HUB_ENABLE_HF_TRANSFER=1 uv --directory "$REPO_ROOT" run hf download \
    "$HF_REPO" "$GGUF_NAME" --local-dir "$MODEL_DIR"
fi

# 2. Install serve script
mkdir -p "$HOME/bin"
cp "$REPO_ROOT/scripts/qwen-coder-3b-serve" "$HOME/bin/qwen-coder-3b-serve" \
  && chmod +x "$HOME/bin/qwen-coder-3b-serve"
echo "installed: $HOME/bin/qwen-coder-3b-serve"

# 3. Fetch the official chat template. The GGUF-embedded template emits inline
#    JSON for tool calls instead of <tool_call>...</tool_call> blocks, so
#    llama-server can't surface structured tool_calls. Verified failing with
#    tool-call-test against the embedded template on 2026-05-23.
TEMPLATE_DEST_DIR="$MODEL_DIR/templates"
TEMPLATE_DEST="$TEMPLATE_DEST_DIR/qwen2.5-coder-3b-official.jinja"
if [[ -f "$TEMPLATE_DEST" ]]; then
  echo "template present: $TEMPLATE_DEST"
else
  echo "fetching official chat template"
  DEST_DIR="$TEMPLATE_DEST_DIR" \
    DEST="$TEMPLATE_DEST" \
    TOKCONF_URL="https://huggingface.co/Qwen/Qwen2.5-Coder-3B-Instruct/resolve/main/tokenizer_config.json" \
    "$REPO_ROOT/scripts/fetch-template"
fi

# 4. Validate
echo
echo "qwen-coder-3b install complete."
echo "Test with:"
echo "  qwen-coder-3b-serve                              # terminal 1"
echo "  ALIAS=local-qwen2.5-coder-3b tool-call-test      # terminal 2"
echo "  pi --model local-qwen2.5-coder-3b                # terminal 2"
