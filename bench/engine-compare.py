#!/usr/bin/env -S uv run --quiet --
# /// script
# requires-python = ">=3.11"
# dependencies = ["httpx>=0.27"]
# ///
"""
Cross-engine throughput comparison: llama.cpp vs higgs (and any other
OpenAI-compatible /v1/chat/completions server).

Sends identical streamed chat completions to multiple endpoints, measures
time-to-first-token (prefill latency proxy) and decode tokens/sec.

Usage:
    uv run bench/engine-compare.py \\
        --endpoint name=llamacpp,url=http://127.0.0.1:8080/v1,model=qwen3-coder-30b-a3b \\
        --endpoint name=higgs,url=http://127.0.0.1:8002/v1,model=qwen3-1.7b \\
        --prompt "Write a Python function that reverses a string." \\
        --max-tokens 256 \\
        --runs 3
"""
import argparse, json, time, sys
from dataclasses import dataclass
from statistics import mean, stdev
import httpx


@dataclass
class Endpoint:
    name: str
    url: str
    model: str


def parse_endpoint(spec: str) -> Endpoint:
    parts = dict(p.split("=", 1) for p in spec.split(","))
    return Endpoint(parts["name"], parts["url"], parts["model"])


def run_one(ep: Endpoint, prompt: str, max_tokens: int) -> dict:
    payload = {
        "model": ep.model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "stream": True,
    }
    t0 = time.perf_counter()
    t_first_token = None
    tokens = 0
    with httpx.stream("POST", f"{ep.url}/chat/completions",
                      json=payload, headers={"Content-Type": "application/json"},
                      timeout=300.0) as r:
        r.raise_for_status()
        for line in r.iter_lines():
            if not line or not line.startswith("data: "):
                continue
            chunk = line[6:]
            if chunk == "[DONE]":
                break
            try:
                obj = json.loads(chunk)
            except json.JSONDecodeError:
                continue
            delta = obj.get("choices", [{}])[0].get("delta", {})
            content = delta.get("content")
            if content:
                if t_first_token is None:
                    t_first_token = time.perf_counter()
                tokens += 1
    t_end = time.perf_counter()
    if t_first_token is None:
        t_first_token = t_end
    return {
        "ttft_ms": (t_first_token - t0) * 1000,
        "decode_s": t_end - t_first_token,
        "tokens": tokens,
        "decode_tps": tokens / max(t_end - t_first_token, 1e-6),
        "total_s": t_end - t0,
    }


def fmt(name, results, prompt_chars):
    ttft = [r["ttft_ms"] for r in results]
    decode_tps = [r["decode_tps"] for r in results]
    tokens = [r["tokens"] for r in results]
    s = lambda xs: f"{mean(xs):7.2f} ± {stdev(xs):5.2f}" if len(xs) > 1 else f"{mean(xs):7.2f}"
    print(f"{name:18s} TTFT={s(ttft)} ms  decode={s(decode_tps)} tok/s  tokens={mean(tokens):.0f}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--endpoint", action="append", required=True,
                    help="name=...,url=...,model=...")
    ap.add_argument("--prompt", required=True)
    ap.add_argument("--max-tokens", type=int, default=256)
    ap.add_argument("--runs", type=int, default=3)
    args = ap.parse_args()
    endpoints = [parse_endpoint(e) for e in args.endpoint]
    prompt_chars = len(args.prompt)
    print(f"Prompt: {prompt_chars} chars · max_tokens={args.max_tokens} · runs={args.runs}\n")
    for ep in endpoints:
        results = []
        for i in range(args.runs):
            try:
                results.append(run_one(ep, args.prompt, args.max_tokens))
            except Exception as e:
                print(f"  {ep.name} run {i+1} failed: {e}", file=sys.stderr)
        if results:
            fmt(ep.name, results, prompt_chars)


if __name__ == "__main__":
    main()
