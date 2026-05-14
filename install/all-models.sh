#!/usr/bin/env bash
# Run base setup + all model installs in sequence. Total disk: ~127 GB.
# Each step is idempotent and resumable — interrupted downloads pick back up.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> base"
"$REPO_ROOT/install/base.sh"

echo
echo "==> qwen3-coder-30b (~21 GB)"
"$REPO_ROOT/install/qwen3-coder-30b.sh"

echo
echo "==> gpt-oss-20b (~12 GB)"
"$REPO_ROOT/install/gpt-oss-20b.sh"

echo
echo "==> qwen3-coder-next-80b (~38 GB)"
"$REPO_ROOT/install/qwen3-coder-next-80b.sh"

echo
echo "==> glm-4.5-air (~55 GB)"
"$REPO_ROOT/install/glm-4.5-air.sh"

echo
echo "all installs complete. Total models: 4. Total disk: ~127 GB."
