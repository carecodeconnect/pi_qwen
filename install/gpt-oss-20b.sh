#!/usr/bin/env bash
# Install gpt-oss-20b (OpenAI's open MoE, MXFP4 native ~12 GB).
# Idempotent — re-runs are safe.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODEL_DIR="$HOME/models/gpt-oss-20b"
GGUF_NAME="gpt-oss-20b-mxfp4.gguf"
HF_REPO="ggml-org/gpt-oss-20b-GGUF"

mkdir -p "$MODEL_DIR"

# 1. Download GGUF if missing
if [[ -f "$MODEL_DIR/$GGUF_NAME" ]]; then
  echo "model present: $MODEL_DIR/$GGUF_NAME ($(du -h "$MODEL_DIR/$GGUF_NAME" | cut -f1))"
else
  echo "downloading $GGUF_NAME (~12 GB)"
  HF_HUB_ENABLE_HF_TRANSFER=1 uv --directory "$REPO_ROOT" run hf download \
    "$HF_REPO" "$GGUF_NAME" --local-dir "$MODEL_DIR"
fi

# 2. Install serve script
mkdir -p "$HOME/bin"
cp "$REPO_ROOT/scripts/gptoss-serve" "$HOME/bin/gptoss-serve" && chmod +x "$HOME/bin/gptoss-serve"
echo "installed: $HOME/bin/gptoss-serve"

# 3. No template override needed — gpt-oss embeds a correct template.

# 4. Validate
echo
echo "gpt-oss-20b install complete."
echo "Test with:"
echo "  gptoss-serve                          # terminal 1"
echo "  ALIAS=local-gpt-oss-20b tool-call-test   # terminal 2"
echo "  pi --model local-gpt-oss-20b          # terminal 2"
