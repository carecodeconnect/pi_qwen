#!/usr/bin/env bash
# Throughput benchmark for the Qwen3-30B-A3B GGUF.
#
# Reports prompt-processing (pp) and token-generation (tg) speeds in tok/s
# using llama-bench (ships with llama.cpp).
#
# Stop qwen-serve first — llama-bench wants exclusive GPU access for
# clean numbers. Otherwise you're measuring contention, not throughput.
set -euo pipefail

MODEL="${MODEL:-$HOME/models/qwen3-30b-a3b/Qwen3-30B-A3B-Q5_K_M.gguf}"
NGL="${NGL:-99}"
FA="${FA:-1}"
# Comma-separated batch sizes for prompt processing and token generation.
PP="${PP:-512}"
TG="${TG:-128}"
REPS="${REPS:-3}"

if [[ ! -f "$MODEL" ]]; then
  echo "error: model not found at $MODEL" >&2
  exit 1
fi

if ! command -v llama-bench >/dev/null 2>&1; then
  echo "error: llama-bench not found on PATH" >&2
  echo "install with: brew install llama.cpp" >&2
  exit 1
fi

# Warn if the server is already running on the default port — it'll skew results.
if lsof -i :8080 -sTCP:LISTEN >/dev/null 2>&1; then
  echo "warning: something is listening on :8080 (qwen-serve?)." >&2
  echo "         stop it before benchmarking for clean numbers." >&2
  echo
fi

echo "model:  $MODEL"
echo "ngl=$NGL  fa=$FA  pp=$PP  tg=$TG  reps=$REPS"
echo

exec llama-bench \
  -m "$MODEL" \
  -ngl "$NGL" \
  -fa "$FA" \
  -p "$PP" \
  -n "$TG" \
  -r "$REPS"
