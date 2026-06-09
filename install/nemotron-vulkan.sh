#!/usr/bin/env bash
# Install the P53 Vulkan stack: prebuilt Vulkan llama.cpp + Nemotron-Nano GGUFs.
# Target: ThinkPad P53, Quadro RTX 4000 (8 GB, Turing 7.5), Ubuntu 26.04.
# See docs/13-p53-vulkan-gpu.md for why Vulkan instead of CUDA.
# Idempotent — re-runs are safe (downloads resume, extraction skipped if present).
set -euo pipefail

LLAMA_TAG="${LLAMA_TAG:-b9581}"                  # bump to a newer llama.cpp release as needed
VK_DIR="$HOME/llama-vulkan"
MODEL_DIR="$HOME/models"
mkdir -p "$VK_DIR" "$MODEL_DIR"

# --- 1. prebuilt Vulkan llama.cpp (no CUDA toolchain needed) ----------------
if [[ -x "$VK_DIR/$LLAMA_TAG/llama-server" ]]; then
  echo "llama.cpp (Vulkan, $LLAMA_TAG) present"
else
  echo "downloading llama.cpp Vulkan prebuilt ($LLAMA_TAG)"
  url="https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_TAG}/llama-${LLAMA_TAG}-bin-ubuntu-vulkan-x64.tar.gz"
  curl -L -C - -o "$VK_DIR/llama-vulkan.tar.gz" "$url"
  tar -xzf "$VK_DIR/llama-vulkan.tar.gz" -C "$VK_DIR"
  # tarball extracts to build/bin/* ; normalise to $VK_DIR/$LLAMA_TAG/
  if [[ -d "$VK_DIR/build/bin" ]]; then mv "$VK_DIR/build/bin" "$VK_DIR/$LLAMA_TAG"; rmdir "$VK_DIR/build" 2>/dev/null || true; fi
  [[ -x "$VK_DIR/$LLAMA_TAG/llama-server" ]] || { echo "extract layout unexpected — check $VK_DIR" >&2; find "$VK_DIR" -name llama-server; exit 1; }
fi

# --- 2. GGUFs (resumable direct download; ollama's HF pull tends to time out) ---
dl() {  # repo  file  dest
  local repo="$1" file="$2" dest="$3"
  if [[ -f "$dest" ]] && [[ "$(stat -c %s "$dest")" -gt 1000000000 ]]; then
    echo "model present: $dest ($(du -h "$dest" | cut -f1))"; return
  fi
  echo "downloading $(basename "$dest")"
  curl -L -C - -o "$dest" "https://huggingface.co/${repo}/resolve/main/${file}"
}
dl "bartowski/nvidia_Llama-3.1-Nemotron-Nano-8B-v1-GGUF" \
   "nvidia_Llama-3.1-Nemotron-Nano-8B-v1-Q4_K_M.gguf" \
   "$MODEL_DIR/nemotron-nano-8b-Q4_K_M.gguf"
dl "bartowski/nvidia_Llama-3.1-Nemotron-Nano-4B-v1.1-GGUF" \
   "nvidia_Llama-3.1-Nemotron-Nano-4B-v1.1-Q4_K_M.gguf" \
   "$MODEL_DIR/nemotron-nano-4b-Q4_K_M.gguf"

# --- 3. lenient Llama-3.1 tools chat template -------------------------------
# The GGUF-embedded Nemotron template raises "roles must alternate" on pi's agent
# loop. llama.cpp's meta-llama-Llama-3.1-8B-Instruct.jinja is role-lenient and works
# with the tool parser (Nano is Llama-3.1-derived → same tokenizer). serve uses it
# via CHAT_TEMPLATE.
TPL="$MODEL_DIR/templates/llama-3.1-instruct-tools.jinja"
mkdir -p "$MODEL_DIR/templates"
if [[ -f "$TPL" ]]; then
  echo "chat template present: $TPL"
else
  echo "fetching Llama-3.1 tools chat template"
  curl -fsSL "https://raw.githubusercontent.com/ggml-org/llama.cpp/master/models/templates/meta-llama-Llama-3.1-8B-Instruct.jinja" -o "$TPL"
fi

echo
echo "done. Serve + test:"
echo "  ./scripts/nemotron-vulkan-serve                         # 8B on :8080 (Quadro)"
echo "  ALIAS=nemotron-nano-8b ./scripts/nemotron-vulkan-test   # tool-call gate + diagnostics"
echo "  MODEL=\$HOME/models/nemotron-nano-4b-Q4_K_M.gguf ALIAS=nemotron-nano-4b ./scripts/nemotron-vulkan-serve  # 4B"
