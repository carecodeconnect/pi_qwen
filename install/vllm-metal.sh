#!/usr/bin/env bash
# Install vllm-project/vllm-metal (the official Apple Silicon plugin to
# upstream vLLM). Idempotent — re-runs are safe.
#
# Why vllm-metal over vllm-mlx: the maintainer of waybarrios/vllm-mlx
# announced in 2026-02-28 (vllm-mlx#123) that further work is going into
# vllm-project/vllm-metal instead. vllm-metal tracks upstream vLLM closely,
# so it inherits fixes — notably the gpt-oss tool-call parser fix from
# vllm#26083 — that vllm-mlx 0.3.0 doesn't have.
#
# See docs/07-engines.md "vllm-project/vllm-metal" for empirical results.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV="${VENV:-$HOME/.venv-vllm-metal}"

# 1. Install vllm-metal via the upstream installer (creates $VENV with vllm
#    core + metal plugin + mlx deps). Idempotent — fast re-run if present.
if [[ -f "$VENV/bin/vllm" ]]; then
  echo "vllm-metal already installed at $VENV"
else
  echo "installing vllm-metal via upstream installer (~5-10 min, ~5 GB)…"
  curl -fsSL https://raw.githubusercontent.com/vllm-project/vllm-metal/main/install.sh | bash
fi

# 2. Install the wrapper
mkdir -p "$HOME/bin"
cp "$REPO_ROOT/scripts/vllm-metal-serve" "$HOME/bin/vllm-metal-serve" && chmod +x "$HOME/bin/vllm-metal-serve"
echo "installed: $HOME/bin/vllm-metal-serve"

# 3. Final note
echo
echo "vllm-metal install complete."
echo "Start with:"
echo "  vllm-metal-serve mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit-DWQ"
echo
echo "Wire into pi via ~/.pi/agent/models.json — see docs/07-engines.md."
