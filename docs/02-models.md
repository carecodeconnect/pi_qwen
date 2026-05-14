# Models

Which models work on a 64 GB M1 Max with pi, which don't, and what's queued for testing.

## Model comparison

Four candidates work end-to-end with pi on this hardware:

- **Qwen3-Coder-30B-A3B-Instruct** (MoE, ~3 B active of 30 B, Q5_K_M, ~20 GiB) — **current default**. Coder-tuned weights, strong tool-call coherence, balanced speed and quality on real coding tasks. Upstream benchmarks: [Qwen3-Coder blog](https://qwenlm.github.io/blog/qwen3-coder/).
- **Qwen3-Coder-Next-80B-A3B-Instruct** (MoE, **3 B active** of 80 B, Q3_K_M, ~36 GiB) — **long-context winner.** Same 3 B active params as the 30B default, scaled total capacity. Decode is ~37% slower (32 vs 51 tok/s) but prefill is nearly flat with context (only 6% drop from pp512→pp8192 vs 30B's 31%) — at long contexts it nearly catches the 30B. See [`qwennext-serve`](./03-serving.md#qwennext-serve). Upstream benchmarks: [Qwen3-Coder blog](https://qwenlm.github.io/blog/qwen3-coder/).
- **gpt-oss-20b** (MoE, ~3.6 B active of 21 B, MXFP4, ~11 GiB) — **fastest**. Clean tool calls, ~1.2–1.6× faster than Qwen-30B on the same prompt sweep (see [docs/05-benchmarking.md](./05-benchmarking.md)). Generalist-reasoning-tuned rather than coder-specialized; survey and Q&A feel just as good, dense codegen quality has not been fully evaluated. Upstream benchmarks: [OpenAI gpt-oss announcement](https://openai.com/index/introducing-gpt-oss/).
- **GLM-4.5-Air** (MoE, ~12 B active of 106 B, Unsloth UD-Q3_K_XL, ~51 GiB) — **marginal but works.** Agent-tuned, clean tool calls, decode ~20 tok/s (~2.5× slower than Qwen-30B — see [docs/05-benchmarking.md](./05-benchmarking.md)). Needs a Metal wired-memory cap bump (see [troubleshooting](./06-troubleshooting.md#kiogpucommandbuffercallbackerroroutofmemory-during-inference)). Upstream benchmarks: [Z.ai GLM-4.5 blog](https://z.ai/blog/glm-4.5).

## Tested and rejected

Documenting what didn't work so the same paths don't get retried. Both removed from `config/models.json`, the serve scripts, and the disk; the GGUFs are not in the Quickstart path.

- **Devstral-Small-2507** (24 B **dense**, Unsloth UD-Q5_K_XL, ~17 GiB) — **failed: bandwidth + tool-call coherence.**
  - Decode ~5× slower than Qwen (~11 tok/s vs ~51 tok/s) — dense 24 B saturates Apple Silicon's unified-memory bandwidth.
  - Asked to enumerate the repo, Devstral emitted a runaway `find` whose `-name` clauses looped duplicates for hundreds of patterns before truncation.
  - **Lesson:** dense ≥ ~20 B is bandwidth-bound on M1 Max regardless of quant — stick to MoE with low active params.
- **DeepSeek-Coder-V2-Lite-Instruct** (16 B MoE, **2.4 B active**, Q5_K_M, ~12 GB) — **failed: model not trained for structured tool calls.**
  - Architecturally a perfect fit (smallest-active-params coder we evaluated); chat works fine.
  - But the upstream `chat_template` is 459 bytes total and renders only `user`/`assistant`/`system` roles with no `<tool_call>` envelope — the model was never trained to emit structured tool calls. Asked to call `get_weather`, it suggested *external* weather websites instead.
  - No template-fetch trick recovers this — the *model* doesn't speak tool calling.
  - **Lesson:** models released before ~mid-2024 (DeepSeek-Coder-V2, CodeLlama, StarCoder-2, Yi-Coder, …) generally predate the structured tool-call norm and are likely to fail the same way. Always run `tool-call-test` before trusting an older model.

## Next model trials

Candidates queued for testing on this same 64 GB M1 Max. All MoE (dense ≥24 B is ruled out by the Devstral result) and known to have working structured tool calling in current llama.cpp.

- **[gpt-oss-120b](https://huggingface.co/openai/gpt-oss-120b)** (MoE, ~5.1 B active of 117 B, MXFP4 native, ~63 GB) — **cleanest scale-up of the gpt-oss-20b favorite.** Same chat template, same `--jinja`-only wiring, same sampler recipe. The catch: 63 GB weights on a 64 GB Mac leave ~1 GB headroom — forces `CTX` to 16–32 K and minimal background apps. Similar tightness to vanilla `Q3_K_M` GLM, which is why GLM dropped to UD-Q3_K_XL. Upstream benchmarks: [OpenAI gpt-oss announcement](https://openai.com/index/introducing-gpt-oss/).
- **[Llama 4 Scout](https://huggingface.co/meta-llama/Llama-4-Scout-17B-16E-Instruct)** (MoE, **17 B active** of 109 B, UD-Q3/Q4, ~50–60 GB) — **expected to underperform Qwen-Coder-Next.** 17 B active is much higher than ideal for Apple Silicon's bandwidth ceiling; decode will be slower than the 3 B-active alternatives despite a similar total-parameter count. Not agent-tuned the way GLM-Air is. Worth testing only to confirm the bandwidth-vs-active-params hypothesis empirically.

Skipped at this hardware tier: DeepSeek-V3/V3.1/V3.2 (~200 GB+ at Q2 — see [DeepSeek note](#a-note-on-deepseek-for-this-hardware) below), Kimi-K2/K2.6 (~350 GB at dynamic 2-bit), Qwen3-Coder-480B (~150 GB at Q3), MiniMax-M1, Mixtral 8x22B (39 B active = same bandwidth death as Devstral). All need a 128 GB+ Mac to be worth the disk space.

## A note on DeepSeek for this hardware

DeepSeek doesn't currently ship a model that's *both* coder-tuned, small enough for a 64 GB Mac, *and* trained for structured tool calls. The matrix as of May 2026:

- **DeepSeek-Coder-V2-Lite** (16 B/2.4 B active) — small enough, but no tool-call training (failed above).
- **DeepSeek-Coder-V2-Instruct** (236 B/21 B active) — tool calls work in V3+ post-training, but too big at any quant for 64 GB.
- **DeepSeek-V3 / V3.1 / V3.2-Exp** (671 B/37 B active) — strong tool calling, but ~200–250 GB at dynamic 2-bit; needs a 192 GB+ Mac.
- **DeepSeek-R1-Distill-Qwen-14B / 32B** — dense distillations into Qwen, would be the only DeepSeek-flavored option that fits, but: (a) dense 32 B is Devstral territory, (b) the distillations target *reasoning* not *coding* and are not trained for tool calls in the same shape pi expects.

Net: there is no DeepSeek model that satisfies all three constraints on a 64 GB Mac today. Qwen3-Coder and GLM-4.5-Air fill the slot DeepSeek would otherwise occupy.

## Choosing a quant

For the Qwen3-Coder-30B default, the trade-off is:

| Quant     | File size | Quality | Notes                                 |
|-----------|-----------|---------|---------------------------------------|
| Q4_K_M    | ~18 GB    | Good    | Default if RAM is tight (32 GB Macs). |
| **Q5_K_M**| ~21 GB    | Better  | Sweet spot for 64 GB+ Macs.           |
| Q6_K      | ~25 GB    | Great   | Marginal gain over Q5; rarely worth.  |
| Q8_0      | ~32 GB    | Near-FP | Diminishing returns; long load times. |
| Q3_K_M    | ~15 GB    | Fair    | For users with very limited disk space. |

Memory budget ≈ model size + KV cache + ~1 GB overhead. KV cache for Qwen3-Coder-30B is ~96 KB/token at fp16:

| Context | KV cache | Total RAM (Q5_K_M) | Fits on   |
|--------:|---------:|-------------------:|-----------|
|     32k |    ~3 GB |             ~25 GB | 32 GB Mac |
|     64k |    ~6 GB |             ~28 GB | 32 GB Mac (tight) |
| **131k**|   **~12 GB** |          **~34 GB** | **64 GB Mac (default)** |
|    262k |   ~24 GB |             ~46 GB | 64 GB Mac (aggressive) |

Tip: add `--cache-type-k q8_0 --cache-type-v q8_0` to `llama-server` (already baked into `qwennext-serve` and `glmair-serve`) to halve KV-cache memory at negligible quality cost — that lets a 64 GB Mac comfortably reach 262 K, or push to ~512 K.
