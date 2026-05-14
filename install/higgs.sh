#!/usr/bin/env bash
# Install higgs (Rust + MLX inference server, no Xcode required).
# Idempotent — re-runs are safe.
#
# Default model: mlx-community/Qwen3-1.7B-4bit (smallest known-working
# tool-call-capable MLX model in this repo's testing). Override with the
# MODEL env var: `MODEL=mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit
# install/higgs.sh` etc.
#
# See docs/07-engines.md "Rust + MLX: higgs" for the full story including
# the no-Xcode rationale and empirical tool-call test results.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODEL="${MODEL:-mlx-community/Qwen3-1.7B-4bit}"
MODEL_NAME_LOCAL="${MODEL_NAME_LOCAL:-$(echo "$MODEL" | awk -F/ '{print tolower($2)}' | sed 's/-4bit//;s/-instruct//')}"
PORT="${PORT:-8002}"
CONFIG_FILE="$HOME/.config/higgs/config.toml"

# 1. Install higgs via Homebrew tap (no Xcode, no Apple ID required)
if command -v higgs >/dev/null 2>&1; then
  echo "higgs already installed: $(higgs --version 2>&1 | head -1)"
else
  echo "installing higgs via Homebrew tap (panbanda/brews)…"
  brew install panbanda/brews/higgs
fi

# 2. Download the MLX model (idempotent — hf skips if cached)
echo "fetching $MODEL via hf (idempotent)…"
HF_HUB_ENABLE_HF_TRANSFER=1 hf download "$MODEL" >/dev/null

# 3. Initialize config if missing, then ensure server binds loopback and
#    the model is registered.
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "initializing $CONFIG_FILE"
  higgs init >/dev/null
fi

# Idempotently inject our model entry if not already present.
if ! grep -q "path = \"$MODEL\"" "$CONFIG_FILE"; then
  echo "adding $MODEL ($MODEL_NAME_LOCAL) to $CONFIG_FILE"
  cat >> "$CONFIG_FILE" <<EOF

# Added by install/higgs.sh
[[models]]
path = "$MODEL"
name = "$MODEL_NAME_LOCAL"
mlx_profile = "balanced"
batch = false
EOF
fi

# Tighten the server binding to loopback + the agreed-on port (idempotent).
# Match either the default 0.0.0.0 or a previously-set value.
sed -i.bak -E "s/^host = .*/host = \"127.0.0.1\"/" "$CONFIG_FILE"
sed -i.bak -E "s/^port = .*/port = $PORT/" "$CONFIG_FILE"
rm -f "$CONFIG_FILE.bak"

# 4. Validate config
echo
higgs doctor 2>&1 | tail -8

# 5. Final note
echo
echo "higgs install complete."
echo "Start with:"
echo "  higgs start                                # background daemon"
echo "  higgs stop                                 # stop daemon"
echo "  curl http://127.0.0.1:$PORT/v1/models      # confirm model loaded"
echo
echo "Wire into pi via ~/.pi/agent/models.json:"
echo '  Add a "local-higgs" provider entry pointing at http://127.0.0.1:'"$PORT"'/v1'
echo "  See docs/07-engines.md for the exact JSON snippet."
echo
echo "Verify tool calls survive the engine swap:"
echo "  PORT=$PORT ALIAS=$MODEL_NAME_LOCAL tool-call-test"
