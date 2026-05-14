# Benchmarking

How to measure inference throughput on your hardware and how to read the numbers.

## Throughput (`bench/throughput.sh`)

Reports raw inference speed via `llama-bench` — prompt processing (`pp`, prefill) and token generation (`tg`, decode), both in tok/s. This measures the model + your hardware, **not pi**.

```bash
# Stop any running llama-server first so the GPU isn't contended
serve-stop
./bench/throughput.sh
```

For a richer sweep — multiple prompt sizes, multiple generation lengths, and a combined prefill+decode test that resembles a real pi turn — call `llama-bench` directly:

```bash
llama-bench \
  -m ~/models/qwen3-coder-30b-a3b/Qwen3-Coder-30B-A3B-Instruct-Q5_K_M.gguf \
  -p 512,2048,8192 \
  -n 128,512 \
  -pg 8192,128 \
  -ngl 99 -fa 1 -r 3
```

## Real runs

Apple M1 Max, 64 GB, llama.cpp build `2e97c5f96 (9100)`.

**Qwen3-Coder-30B-A3B (Q5_K_M, 20.23 GiB, 30.53 B params, 3 B active)**

```
| model                          |      size |  params | backend  | threads | fa |          test |             t/s |
| ------------------------------ | --------: | ------: | -------- | ------: | -: | ------------: | --------------: |
| qwen3moe 30B.A3B Q5_K - Medium | 20.23 GiB | 30.53 B | BLAS,MTL |       8 |  1 |         pp512 |   593.80 ± 4.38 |
| qwen3moe 30B.A3B Q5_K - Medium | 20.23 GiB | 30.53 B | BLAS,MTL |       8 |  1 |        pp2048 |   554.40 ± 0.51 |
| qwen3moe 30B.A3B Q5_K - Medium | 20.23 GiB | 30.53 B | BLAS,MTL |       8 |  1 |        pp8192 |   409.13 ± 7.86 |
| qwen3moe 30B.A3B Q5_K - Medium | 20.23 GiB | 30.53 B | BLAS,MTL |       8 |  1 |         tg128 |    50.76 ± 0.21 |
| qwen3moe 30B.A3B Q5_K - Medium | 20.23 GiB | 30.53 B | BLAS,MTL |       8 |  1 |         tg512 |    50.00 ± 0.11 |
| qwen3moe 30B.A3B Q5_K - Medium | 20.23 GiB | 30.53 B | BLAS,MTL |       8 |  1 |  pp8192+tg128 |   356.51 ± 2.71 |
```

**Qwen3-Coder-Next-80B-A3B-Instruct (Q3_K_M, 35.69 GiB, 79.67 B params, 3 B active)**

```
| model                          |      size |  params | backend  | threads | fa |          test |             t/s |
| ------------------------------ | --------: | ------: | -------- | ------: | -: | ------------: | --------------: |
| qwen3next 80B.A3B Q3_K - Medium| 35.69 GiB | 79.67 B | BLAS,MTL |       8 |  1 |         pp512 |   407.39 ± 0.89 |
| qwen3next 80B.A3B Q3_K - Medium| 35.69 GiB | 79.67 B | BLAS,MTL |       8 |  1 |        pp2048 |   398.95 ± 3.05 |
| qwen3next 80B.A3B Q3_K - Medium| 35.69 GiB | 79.67 B | BLAS,MTL |       8 |  1 |        pp8192 |   381.04 ± 1.87 |
| qwen3next 80B.A3B Q3_K - Medium| 35.69 GiB | 79.67 B | BLAS,MTL |       8 |  1 |         tg128 |    31.93 ± 0.10 |
| qwen3next 80B.A3B Q3_K - Medium| 35.69 GiB | 79.67 B | BLAS,MTL |       8 |  1 |         tg512 |    31.94 ± 0.26 |
| qwen3next 80B.A3B Q3_K - Medium| 35.69 GiB | 79.67 B | BLAS,MTL |       8 |  1 |  pp8192+tg128 |   323.00 ± 2.03 |
```

**gpt-oss-20b (MXFP4, 11.27 GiB, 20.91 B params, ~3.6 B active)**

```
| model                 |      size |  params | backend  | threads | fa |          test |             t/s |
| --------------------- | --------: | ------: | -------- | ------: | -: | ------------: | --------------: |
| gpt-oss 20B MXFP4 MoE | 11.27 GiB | 20.91 B | BLAS,MTL |       8 |  1 |         pp512 |   755.59 ± 0.90 |
| gpt-oss 20B MXFP4 MoE | 11.27 GiB | 20.91 B | BLAS,MTL |       8 |  1 |        pp2048 |   741.53 ± 1.33 |
| gpt-oss 20B MXFP4 MoE | 11.27 GiB | 20.91 B | BLAS,MTL |       8 |  1 |        pp8192 |   650.61 ± 7.65 |
| gpt-oss 20B MXFP4 MoE | 11.27 GiB | 20.91 B | BLAS,MTL |       8 |  1 |         tg128 |    59.67 ± 0.46 |
| gpt-oss 20B MXFP4 MoE | 11.27 GiB | 20.91 B | BLAS,MTL |       8 |  1 |         tg512 |    60.40 ± 0.31 |
| gpt-oss 20B MXFP4 MoE | 11.27 GiB | 20.91 B | BLAS,MTL |       8 |  1 |  pp8192+tg128 |   544.15 ± 3.87 |
```

**GLM-4.5-Air (Unsloth UD-Q3_K_XL, 51.01 GiB, 110.47 B params, 12 B active)**

```
| model                           |      size |   params | backend  | threads | fa |          test |             t/s |
| ------------------------------- | --------: | -------: | -------- | ------: | -: | ------------: | --------------: |
| glm4moe 106B.A12B Q3_K - Medium | 51.01 GiB | 110.47 B | BLAS,MTL |       8 |  1 |         pp512 |   160.62 ± 1.25 |
| glm4moe 106B.A12B Q3_K - Medium | 51.01 GiB | 110.47 B | BLAS,MTL |       8 |  1 |        pp2048 |   150.45 ± 1.76 |
| glm4moe 106B.A12B Q3_K - Medium | 51.01 GiB | 110.47 B | BLAS,MTL |       8 |  1 |        pp8192 |   116.98 ± 0.47 |
| glm4moe 106B.A12B Q3_K - Medium | 51.01 GiB | 110.47 B | BLAS,MTL |       8 |  1 |         tg128 |    20.57 ± 0.08 |
| glm4moe 106B.A12B Q3_K - Medium | 51.01 GiB | 110.47 B | BLAS,MTL |       8 |  1 |         tg512 |    19.82 ± 0.30 |
| glm4moe 106B.A12B Q3_K - Medium | 51.01 GiB | 110.47 B | BLAS,MTL |       8 |  1 |  pp8192+tg128 |   104.77 ± 1.50 |
```

## Reading the numbers

- **Prefill scaling.** All four models slow down with longer prompts, but at different rates. From pp512→pp8192: Qwen-30B drops 31% (594→409), gpt-oss drops 14% (756→651), GLM drops 27% (161→117), **Qwen-Next drops only 6%** (407→381). The gentle Qwen-Next curve is the standout — at long contexts it nearly matches Qwen-30B's prefill despite starting much slower.
- **Decode is steady within a model** (`tg128` ≈ `tg512`). It's bandwidth-bound, not compute-bound, so generation length barely matters.
- **gpt-oss is ~1.2–1.6× faster than Qwen-30B across the sweep**, with the gap widest at `pp8192+tg128` — the agent-realistic combined run.
- **Qwen-Next vs Qwen-30B is a long-context trade.** Short-prompt prefill is ~30% slower (407 vs 594) and decode is ~37% slower (31.9 vs 50.8), but the long-context numbers converge: at `pp8192` they're within 7% (381 vs 409), and `pp8192+tg128` is within 10% (323 vs 357). Both have 3 B active params, so the decode delta is bandwidth-dominated by the larger total weight footprint (35.69 GiB vs 20.23 GiB).
- **GLM-4.5-Air is ~3–4× slower than Qwen-30B and ~5–6× slower than gpt-oss.** Two effects compound: 12 B active params (4× Qwen's 3 B) means more compute per token, and the 51 GiB weights run right against the 56 GB Metal wired-memory cap, so any page miss is expensive. The architectural prediction (decode slowdown ≈ active-param ratio) holds: 50.8 / 20.6 ≈ 2.5×, matched closely. Coding-agent usable at ~20 tok/s decode, but you feel the long-context prefill.
- **Active params dominate decode.** Qwen-Next (3 B active, 80 B total) decodes at 31.9 tok/s; GLM (12 B active, 106 B total) decodes at 20.6. Despite a larger total footprint, Qwen-Next is faster — confirming the rule we've been operating by since Devstral.
- **MoE throughput moves with quant, batch size, context length, and what else is on the GPU.** Reproduce all runs on your own hardware before reading too much into the deltas.

## Wrapper overrides

```bash
PP=2048 TG=256 REPS=5 ./bench/throughput.sh     # bigger batches, more reps
MODEL=~/models/other.gguf ./bench/throughput.sh # benchmark a different model
NGL=0 ./bench/throughput.sh                     # CPU-only baseline (slow)
```

Run this once after install to confirm your hardware is performing, and again after any quant/flag change to catch regressions.

## Other benchmarks worth knowing about

- **Latency / time-to-first-token** — measures the path pi actually walks. Send timed requests to `/v1/chat/completions` and read the `timings` block llama-server returns.
- **Agent quality** — public coding-agent benchmarks like [Aider's polyglot eval](https://aider.chat/docs/leaderboards/) or HumanEval. They measure the model, not pi-with-the-model.
- **Your own prompt set** — the only thing that measures *your* workflow. A handful of representative tasks from your real work, run twice, eyeballed.
