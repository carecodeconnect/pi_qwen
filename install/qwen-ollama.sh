#!/usr/bin/env bash
# Install the OLLAMA path for agentic pi on the P53 — the WORKING tool-calling route.
# llama-server (Vulkan) drops small-model tool calls (Qwen <function>, Nemotron <TOOLCALL>) on
# this build; ollama bundles correct per-model templates + parsers, so tool calls actually parse.
# ollama also ships its own CUDA runtime (no system CUDA toolkit needed) and runs on the Quadro.
# See docs/13-p53-vulkan-gpu.md. Idempotent.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 1. ollama
if command -v ollama >/dev/null 2>&1; then
  echo "ollama present: $(ollama --version 2>/dev/null | head -1)"
else
  echo "installing ollama (official script)"
  curl -fsSL https://ollama.com/install.sh | sh
fi

# 2. model — Qwen2.5-Coder-7B-Instruct (instruct coder, first-class tool calling)
if ollama list 2>/dev/null | grep -q '^qwen2.5-coder'; then
  echo "model present: qwen2.5-coder"
else
  echo "pulling qwen2.5-coder (~4.7 GB Q4_K_M)"
  ollama pull qwen2.5-coder
fi

# 3. deploy pi provider config (adds the local-ollama provider at :11434)
mkdir -p "$HOME/.pi/agent"
cp "$REPO_ROOT/config/models.json" "$HOME/.pi/agent/models.json"

echo
echo "done. ollama serves at http://127.0.0.1:11434 with clean tool-call parsing."
echo "Run the agent:   pi --model qwen2.5-coder"
echo "(free GPU VRAM first if a llama-server is still loaded: pkill -f llama-server)"
