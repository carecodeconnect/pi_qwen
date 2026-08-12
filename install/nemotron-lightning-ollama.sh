#!/usr/bin/env bash
# Install Nemotron 3.5 Lightning (30B MoE, 3B active) via OLLAMA for agentic pi on the P53.
# The 25 GB Q4_K_M does NOT fit the 8 GB Quadro — ollama runs it ~80/20 CPU/GPU, and the
# sparse 3B-active MoE keeps decode usable (~20 tok/s measured, 91 GiB RAM box).
# REQUIRES ollama >= 0.32 (the hybrid Mamba-2 + MoE arch is unknown to older builds).
# See docs/13-p53-vulkan-gpu.md. Idempotent.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 1. ollama — needs a 2026-era build for the Nemotron 3.5 architecture
if command -v ollama >/dev/null 2>&1; then
  echo "ollama present: $(ollama --version 2>/dev/null | head -1)"
  echo "NOTE: nemotron-3.5-lightning needs ollama >= 0.32; re-run the official"
  echo "      installer to upgrade if older: curl -fsSL https://ollama.com/install.sh | sh"
else
  echo "installing ollama (official script)"
  curl -fsSL https://ollama.com/install.sh | sh
fi

# 2. model — 25 GB download
if ollama list 2>/dev/null | grep -q '^nemotron-3.5-lightning:30b-a3b-q4_K_M'; then
  echo "model present: nemotron-3.5-lightning:30b-a3b-q4_K_M"
else
  echo "pulling nemotron-3.5-lightning:30b-a3b-q4_K_M (~25 GB Q4_K_M)"
  ollama pull nemotron-3.5-lightning:30b-a3b-q4_K_M
fi

# 3. 64k-context variant — ollama's 4096 default truncates pi's agent loop.
#    Mamba-2 layers hold constant-size state, so 64k costs almost nothing extra.
if ollama list 2>/dev/null | grep -q '^nemotron-3.5-lightning-64k'; then
  echo "variant present: nemotron-3.5-lightning-64k"
else
  tmp="$(mktemp)"
  printf 'FROM nemotron-3.5-lightning:30b-a3b-q4_K_M\nPARAMETER num_ctx 65536\n' > "$tmp"
  ollama create nemotron-3.5-lightning-64k -f "$tmp"
  rm -f "$tmp"
fi

# 4. deploy pi provider config (local-ollama provider at :11434)
mkdir -p "$HOME/.pi/agent"
cp "$REPO_ROOT/config/models.json" "$HOME/.pi/agent/models.json"

echo
echo "done. Run the agent:   pi --provider local-ollama --model nemotron-3.5-lightning-64k"
