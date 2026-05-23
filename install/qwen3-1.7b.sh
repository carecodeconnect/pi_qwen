#!/usr/bin/env bash
# Install Qwen3-1.7B (~1.1 GB Q4_K_M).
# X270/CPU agent default — same base model as jhana-rs (which validated its
# structured tool-calling on the RK3588 NPU). Replaces Qwen3-4B-Instruct-2507
# as the X270 default because TTFT on 4B is too slow on the i7-7600U.
# See docs/12-linux-cpu.md and docs/TODO_x270.md.
# Idempotent — re-runs are safe.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODEL_DIR="$HOME/models/qwen3-1.7b"
GGUF_NAME="Qwen3-1.7B-Q4_K_M.gguf"
HF_REPO="unsloth/Qwen3-1.7B-GGUF"

mkdir -p "$MODEL_DIR"

# 1. Download GGUF if missing
if [[ -f "$MODEL_DIR/$GGUF_NAME" ]]; then
  echo "model present: $MODEL_DIR/$GGUF_NAME ($(du -h "$MODEL_DIR/$GGUF_NAME" | cut -f1))"
else
  echo "downloading $GGUF_NAME (~1.1 GB)"
  HF_HUB_ENABLE_HF_TRANSFER=1 uv --directory "$REPO_ROOT" run hf download \
    "$HF_REPO" "$GGUF_NAME" --local-dir "$MODEL_DIR"
fi

# 2. Install serve script
mkdir -p "$HOME/bin"
cp "$REPO_ROOT/scripts/qwen3-1.7b-serve" "$HOME/bin/qwen3-1.7b-serve" \
  && chmod +x "$HOME/bin/qwen3-1.7b-serve"
echo "installed: $HOME/bin/qwen3-1.7b-serve"

# 3. Fetch the official chat template (from Qwen's base repo, not the Unsloth
#    GGUF). Same rationale as install/qwen-coder-3b.sh: embedded templates emit
#    tool calls in formats llama-server can't parse into structured tool_calls.
TEMPLATE_DEST_DIR="$MODEL_DIR/templates"
TEMPLATE_DEST="$TEMPLATE_DEST_DIR/qwen3-1.7b-official.jinja"
if [[ -f "$TEMPLATE_DEST" ]]; then
  echo "template present: $TEMPLATE_DEST"
else
  echo "fetching official chat template"
  DEST_DIR="$TEMPLATE_DEST_DIR" \
    DEST="$TEMPLATE_DEST" \
    TOKCONF_URL="https://huggingface.co/Qwen/Qwen3-1.7B/resolve/main/tokenizer_config.json" \
    "$REPO_ROOT/scripts/fetch-template"
fi

# 4. Validate
echo
echo "qwen3-1.7b install complete."
echo "Test with:"
echo "  qwen3-1.7b-serve                          # terminal 1"
echo "  ALIAS=local-qwen3-1.7b tool-call-test     # terminal 2"
echo "  pi --model local-qwen3-1.7b               # terminal 2"
