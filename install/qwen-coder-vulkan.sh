#!/usr/bin/env bash
# Install Qwen2.5-Coder-7B-Instruct (Q5_K_M GGUF) + Qwen2.5 tools template for the P53 Vulkan
# stack. Uses the shared Vulkan llama.cpp from install/nemotron-vulkan.sh. See docs/13.
set -euo pipefail
MODEL_DIR="$HOME/models"; mkdir -p "$MODEL_DIR/templates"
GGUF="$MODEL_DIR/qwen2.5-coder-7b-instruct-Q5_K_M.gguf"
if [[ -f "$GGUF" ]] && [[ "$(stat -c %s "$GGUF")" -gt 5000000000 ]]; then
  echo "model present: $GGUF"
else
  echo "downloading Qwen2.5-Coder-7B-Instruct Q5_K_M (~5.4 GB)"
  curl -L -C - -o "$GGUF" \
    "https://huggingface.co/bartowski/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/Qwen2.5-Coder-7B-Instruct-Q5_K_M.gguf"
fi
TPL="$MODEL_DIR/templates/qwen2.5-instruct-tools.jinja"
[[ -f "$TPL" ]] || curl -fsSL "https://raw.githubusercontent.com/ggml-org/llama.cpp/master/models/templates/Qwen-Qwen2.5-7B-Instruct.jinja" -o "$TPL"
echo "done. serve: ./scripts/qwen-coder-vulkan-serve  |  pi --model qwen2.5-coder-7b"
