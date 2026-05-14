#!/usr/bin/env bash
# Install GLM-4.5-Air (Z.ai's agent-tuned MoE, Unsloth UD-Q3_K_XL, ~55 GB
# across two shards). Idempotent — re-runs are safe.
#
# Important: this model needs the macOS Metal wired-memory cap raised
# before it can run inference. See docs/06-troubleshooting.md.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODEL_DIR="$HOME/models/glm-4.5-air"
SHARD_DIR="$MODEL_DIR/UD-Q3_K_XL"
HF_REPO="unsloth/GLM-4.5-Air-GGUF"

mkdir -p "$MODEL_DIR"

# 1. Download shards if missing (llama.cpp auto-loads -00002 when given -00001)
SHARD_1="$SHARD_DIR/GLM-4.5-Air-UD-Q3_K_XL-00001-of-00002.gguf"
SHARD_2="$SHARD_DIR/GLM-4.5-Air-UD-Q3_K_XL-00002-of-00002.gguf"

if [[ -f "$SHARD_1" && -f "$SHARD_2" ]]; then
  echo "model present: $SHARD_DIR ($(du -sh "$SHARD_DIR" | cut -f1))"
else
  echo "downloading UD-Q3_K_XL/* (~55 GB, two shards) — this takes 30-60 min"
  HF_HUB_ENABLE_HF_TRANSFER=1 uv --directory "$REPO_ROOT" run hf download \
    "$HF_REPO" --include "UD-Q3_K_XL/*" --local-dir "$MODEL_DIR"
fi

# 2. Install serve script
mkdir -p "$HOME/bin"
cp "$REPO_ROOT/scripts/glmair-serve" "$HOME/bin/glmair-serve" && chmod +x "$HOME/bin/glmair-serve"
echo "installed: $HOME/bin/glmair-serve"

# 3. No template override — Unsloth's GGUF embeds a corrected template.

# 4. Check the Metal wired-memory cap
current_cap=$(sysctl -n iogpu.wired_limit_mb 2>/dev/null || echo 0)
if [[ "$current_cap" -lt 49152 ]]; then
  echo
  echo "WARNING: macOS Metal wired-memory cap is too low for this model (~51 GB weights)."
  echo "Current: ${current_cap} MB (0 = system default ~44 GB)"
  echo
  echo "Raise it before running glmair-serve:"
  echo "  sudo sysctl iogpu.wired_limit_mb=57344    # 56 GB cap on a 64 GB Mac"
  echo
  echo "Otherwise inference will return HTTP 500 with kIOGPUCommandBufferCallbackErrorOutOfMemory."
  echo "See docs/06-troubleshooting.md for the persistent variant."
fi

# 5. Validate
echo
echo "glm-4.5-air install complete."
echo "Test with:"
echo "  glmair-serve                            # terminal 1"
echo "  ALIAS=local-glm-4.5-air tool-call-test  # terminal 2"
echo "  pi --model local-glm-4.5-air            # terminal 2"
