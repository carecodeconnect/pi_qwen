#!/bin/bash
# Format a Mermaid diagram with mermaid-formatter (mermaidfmt CLI).
# Usage:
#   format.sh diagram.mmd            # write in place
#   format.sh --check diagram.mmd    # diff against formatted, exit 1 if changes needed
#
# What it normalizes:
# - Indentation + whitespace
# - Collapses consecutive blank lines
# - Arrow message spacing (e.g. `A->>B:msg` -> `A ->> B: msg`)
# - Nesting indent for block keywords
# Supports sequence, flowchart, class, state, etc.
#
# Notes:
# - First run downloads mermaid-formatter into the npx cache (~1 MB).
# - Mermaid's ecosystem doesn't have a strict canonical formatter the way
#   Rust has `cargo fmt`; this is the closest available consistency helper.

set -euo pipefail

CHECK=0
if [ "${1:-}" = "--check" ]; then
    CHECK=1
    shift
fi

if [ $# -lt 1 ]; then
    echo "Usage: $0 [--check] diagram.mmd"
    exit 1
fi

INPUT="$1"

if [ ! -f "$INPUT" ]; then
    echo "Error: File not found: $INPUT"
    exit 1
fi

if [ "$CHECK" -eq 1 ]; then
    echo "Checking: $INPUT"
    if diff -u "$INPUT" <(npx -y -p mermaid-formatter mermaidfmt "$INPUT") > /dev/null; then
        echo "✓ Already formatted"
    else
        echo "✗ File needs formatting — re-run without --check to fix"
        echo "  Diff:"
        diff -u "$INPUT" <(npx -y -p mermaid-formatter mermaidfmt "$INPUT") || true
        exit 1
    fi
else
    echo "Formatting: $INPUT (write)"
    npx -y -p mermaid-formatter mermaidfmt -w "$INPUT"
    echo "✓ Formatted"
fi
