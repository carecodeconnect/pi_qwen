#!/usr/bin/env bash
# Install Qwen2.5-Coder-1.5B-Instruct (~1.1 GB Q4_K_M).
# Experimental X270/CPU candidate — coder-specialised, closest size class to
# the current Qwen3-1.7B default. The 3B sibling FAILs tool-call-test under
# tool_choice: auto (markdown JSON wrapper bug shared across the 2.5-Coder
# family per llama.cpp #12279); the 1.5B has no public llama.cpp tool-call
# data either way, so this install exists to let us verify locally.
# See docs/12-linux-cpu.md and docs/TODO_x270.md.
# Idempotent — re-runs are safe.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODEL_DIR="$HOME/models/qwen2.5-coder-1.5b"
GGUF_NAME="qwen2.5-coder-1.5b-instruct-q4_k_m.gguf"
HF_REPO="Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF"

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
cp "$REPO_ROOT/scripts/qwen-coder-1.5b-serve" "$HOME/bin/qwen-coder-1.5b-serve" \
  && chmod +x "$HOME/bin/qwen-coder-1.5b-serve"
echo "installed: $HOME/bin/qwen-coder-1.5b-serve"

# 3. Fetch the official chat template. Same rationale as install/qwen-coder-3b.sh:
#    the GGUF-embedded template emits inline JSON for tool calls instead of
#    <tool_call>...</tool_call> blocks, so llama-server can't surface structured
#    tool_calls. Whether the 1.5B inherits this is precisely what running
#    tool-call-test against this install is meant to determine.
TEMPLATE_DEST_DIR="$MODEL_DIR/templates"
TEMPLATE_DEST="$TEMPLATE_DEST_DIR/qwen2.5-coder-1.5b-official.jinja"
if [[ -f "$TEMPLATE_DEST" ]]; then
  echo "template present: $TEMPLATE_DEST"
else
  echo "fetching official chat template"
  DEST_DIR="$TEMPLATE_DEST_DIR" \
    DEST="$TEMPLATE_DEST" \
    TOKCONF_URL="https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct/resolve/main/tokenizer_config.json" \
    "$REPO_ROOT/scripts/fetch-template"
fi

# 4. Validate
echo
echo "qwen-coder-1.5b install complete."
echo "Test with:"
echo "  qwen-coder-1.5b-serve                          # terminal 1"
echo "  ALIAS=local-qwen2.5-coder-1.5b tool-call-test  # terminal 2 — verifies tool_choice: auto"
echo "  pi --model local-qwen2.5-coder-1.5b            # terminal 2"
