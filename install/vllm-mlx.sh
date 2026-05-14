#!/usr/bin/env bash
# Install vllm-mlx (Python+MLX inference engine, no Xcode required).
# Idempotent — re-runs are safe.
#
# vllm-mlx is the no-Xcode alternative engine path for this repo. It serves
# MLX models with a richer set of tool-call parsers than higgs (17 parsers
# including qwen3_coder, harmony, glm47, hermes, …) and reaches a higher
# percentage of "models that work end-to-end on Apple Silicon."
#
# See docs/07-engines.md "MLX in Python: vllm-mlx" for the empirical results.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

VLLM_MLX_DIR="${VLLM_MLX_DIR:-$HOME/src/vllm-mlx}"
MODEL="${MODEL:-mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit-DWQ}"

# 1. Clone vllm-mlx if missing (idempotent — git pull on existing checkout)
if [[ -d "$VLLM_MLX_DIR/.git" ]]; then
  echo "vllm-mlx already cloned at $VLLM_MLX_DIR, pulling…"
  git -C "$VLLM_MLX_DIR" pull --quiet --ff-only
else
  echo "cloning vllm-mlx → $VLLM_MLX_DIR"
  git clone --quiet https://github.com/waybarrios/vllm-mlx.git "$VLLM_MLX_DIR"
fi

# 2. Create venv + install (idempotent)
if [[ ! -f "$VLLM_MLX_DIR/.venv/bin/vllm-mlx" ]]; then
  echo "creating venv + installing vllm-mlx (~30 s on first run)…"
  (cd "$VLLM_MLX_DIR" && uv venv && uv pip install -e . > /dev/null)
fi
echo "installed: $VLLM_MLX_DIR/.venv/bin/vllm-mlx"

# 3. Download the default model (idempotent — hf skips if cached)
echo "fetching $MODEL via hf (idempotent)…"
HF_HUB_ENABLE_HF_TRANSFER=1 hf download "$MODEL" > /dev/null

# 4. Install the wrapper script
mkdir -p "$HOME/bin"
cp "$REPO_ROOT/scripts/vllm-mlx-serve" "$HOME/bin/vllm-mlx-serve" && chmod +x "$HOME/bin/vllm-mlx-serve"
echo "installed: $HOME/bin/vllm-mlx-serve"

# 5. Final note
echo
echo "vllm-mlx install complete."
echo "Start with:"
echo "  vllm-mlx-serve $MODEL    # terminal 1"
echo
echo "Verify tool calls survive the engine swap:"
echo "  PORT=8001 ALIAS=$MODEL tool-call-test"
echo
echo "Wire into pi via ~/.pi/agent/models.json — see docs/07-engines.md."
