# Linux / CPU (ThinkPad X270-class)

Get pi running against a local Qwen model on Linux x86_64 with no GPU. This is the documented second-class target — see [`docs/TODO_x270.md`](./TODO_x270.md) for the broader plan. The Apple-Silicon path in [`01-quickstart.md`](./01-quickstart.md) stays the reference.

## Hardware floor

Tested on a ThinkPad X270:

- Intel Core **i7-7600U** (Kaby Lake, 2c/4t, AVX2, no AVX-512)
- **14 GiB** DDR4 (≥ 12 GiB free at idle recommended)
- Intel **HD 620** iGPU (unused by default; Vulkan path optional, see below)
- Ubuntu 26.04 Server

Anything smaller (≤ 8 GiB RAM, AVX-only) is out of scope.

## Install

```bash
# 1. System prerequisites
sudo apt update && sudo apt install -y llama.cpp        # Debian trixie+/Ubuntu 26.04+
curl -fsSL https://pi.dev/install.sh | sh               # pi
curl -LsSf https://astral.sh/uv/install.sh | sh         # uv

# 2. From inside the cloned repo
uv sync                                                 # hf + hf_transfer
./install/base.sh                                       # ~/bin scripts + ~/.pi/agent/models.json
./install/qwen3-4b.sh                                   # validated X270 default — see "Model choice" below

# 3. Make sure ~/bin is on PATH
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc

# 4. Smoke test
qwen3-4b-serve                                          # terminal 1
ALIAS=local-qwen3-4b-instruct-2507 tool-call-test       # terminal 2 — must say PASS
pi --model local-qwen3-4b-instruct-2507                 # terminal 2
```

Older distros without `llama.cpp` in apt need to build from source — see [github.com/ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp).

## Model choice

Validated 2026-05-23 on an X270. **Run `tool-call-test` before trusting any model for pi agent loops** — small models often emit the right JSON but in the wrong wrapper, and only structured `tool_calls` survive pi's parser.

| # | Model | Source | Size (Q4) | Decode tok/s | `tool-call-test` (auto) | Real-pi tool use | Use for |
|---|---|---|---|---|---|---|---|
| 1 | **Qwen3-1.7B** | [`unsloth/Qwen3-1.7B-GGUF`](https://huggingface.co/unsloth/Qwen3-1.7B-GGUF) | ~1.1 GB | (faster TTFT than 4B) | **PASS** (in jhana-rs Phase 1, also locally 2026-05-23) | **FAIL** — skips tool calls, hallucinates content in real pi sessions | Fast one-shot Q&A only; not for pi agent loops |
| 2 | Qwen3-4B-Instruct-2507 | [`unsloth/Qwen3-4B-Instruct-2507-GGUF`](https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF) | ~2.5 GB | ~3.3 | **PASS** | **PASS** | X270 agent default — pi loops with tool calls |
| 3 | Qwen2.5-Coder-1.5B-Instruct | [`Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF`](https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF) | ~1.1 GB | (similar to 1.7B) | **FAIL** (2026-05-23) | n/a — never gets a parseable tool call | Code completion / non-agent tasks only |
| 4 | Qwen2.5-Coder-3B-Instruct | [`Qwen/Qwen2.5-Coder-3B-Instruct-GGUF`](https://huggingface.co/Qwen/Qwen2.5-Coder-3B-Instruct-GGUF) | ~2.0 GB | ~5.3 | **FAIL** | n/a — same family wrapper bug | Code completion / non-agent tasks only |

**"Real-pi tool use" matters more than `tool-call-test`.** The test confirms the model+template can emit a structured `tool_calls` field for a trivial one-tool prompt. It does *not* predict whether the model will actually *decide* to call a tool in a long pi conversation (4.4k system prompt, many skills + extensions + hooks). Qwen3-1.7B passes the test but, with `--reasoning off` set for TTFT, skips tools entirely in real sessions and hallucinates fake content (e.g. invents `main.py` for a "review the codebase" prompt without calling `bash("ls")`). Qwen3-1.7B's decide-to-call-a-tool step appears partly carried by its thinking-mode deliberation; turning thinking on restores tool calling but pays multi-minute latency per turn at this CPU speed — unworkable. Qwen2.5-Coder-1.5B inherits the **family-wide wrapper bug** (emits raw JSON instead of `<tool_call>` tags, confirmed locally 2026-05-23 and matching upstream reports for 3B/7B/32B in [llama.cpp#12279](https://github.com/ggml-org/llama.cpp/issues/12279)).

The 1.7B default matches the same base model [jhana-rs](https://github.com/carecodeconnect/jhana-rs) runs on the RK3588 NPU — its `src/bin/qwen-tool-test.rs` validated structured `<tool_call>` emission under the official Qwen3 ChatML template (Phase 1 PASS, 2026-05-15). The 4B was the previous X270 default but its TTFT on the i7-7600U was the bottleneck for interactive use; the 1.7B at ~half the weights gets first tokens out noticeably faster while still passing tool-call.

### Why not Qwen2.5-Coder-3B for pi?

It emits the right tool name + arguments but wraps them in a markdown code fence (`` ```json ... ``` ``) instead of `<tool_call>…</tool_call>` tags. llama-server's parser can't extract that into structured `tool_calls`, so pi sees a text response with no tool invocation. Forcing it with `tool_choice: "required"` rescues the call via llama-server's grammar-constrained decoding, but pi uses `tool_choice: "auto"` so this doesn't help in practice. Qwen3-1.7B (and Qwen3-4B-Instruct) follow the wrapper format reliably under `auto` — that's why the Qwen3 family is the default.

This validation finding lives in [`docs/TODO_x270.md`](./TODO_x270.md) and is the reason `install/qwen-coder-3b.sh` exists but is *not* the X270 recommendation.

### Coder-specific variants (untested on this hardware)

There is no native Qwen3-Coder at 4B — the smallest official Qwen3-Coder is the **30B-A3B MoE**, which is interesting on CPU because only 3B params are active per token (≈ dense 3B decode speed). Heavily quantized variants fit in 14 GiB:

| GGUF variant | Size | RAM headroom (14 GiB) | Notes |
|---|---|---|---|
| `UD-IQ1_S` | 8.3 GB | ~5.7 GB | Aggressive, quality risk on MoE |
| `UD-IQ2_M` | 10.1 GB | ~3.9 GB | Balanced |
| `Q2_K` | 10.5 GB | ~3.5 GB | Recommended starting point |
| `Q3_K_S` | 12.4 GB | ~1.6 GB | Highest quality that still fits with KV-cache |
| `Q3_K_M` | 13.7 GB | barely fits | Avoid — KV cache will OOM |

Source: [`unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF`](https://huggingface.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF). Sizes verified via HF `Content-Length` headers on 2026-05-23.

Caveat: heavy quantization (Q2/IQ1) degrades small-active MoE models more than dense models of equivalent size. If you try this path, run `tool-call-test` *and* a real pi session before assuming it works; if the larger quant fits with KV-cache room, prefer it. No install script for this variant yet — pattern after [`install/qwen3-4b.sh`](../install/qwen3-4b.sh) and adjust HF_REPO/GGUF_NAME/MODEL_DIR.

## Chat-template override (mandatory)

All three model install scripts fetch the model's official chat template from its base HF repo and pass it to `llama-server` via `--chat-template-file`. The GGUF-embedded templates emit tool calls in formats llama-server can't parse into structured `tool_calls`. This is the same gotcha [`scripts/qwen-serve`](../scripts/qwen-serve) addresses for Qwen3-Coder-30B-A3B on macOS, and the X270 install scripts do it proactively.

If you're hand-rolling a new model, the pattern is:

```bash
DEST_DIR=~/models/<model>/templates \
  DEST=~/models/<model>/templates/<model>-official.jinja \
  TOKCONF_URL=https://huggingface.co/<org>/<model>/resolve/main/tokenizer_config.json \
  scripts/fetch-template
```

Then point your serve script at the `.jinja` file via `--chat-template-file`.

## Serve-script tuning

`scripts/qwen3-4b-serve` and `scripts/qwen-coder-3b-serve` set CPU-appropriate defaults overridable by env:

| Env | Default | Notes |
|---|---|---|
| `NGL` | `0` | Pure CPU. Try `20`+ on Vulkan-enabled builds with HD 620 (see below). |
| `CTX` | `16384` | KV cache dominates RSS on small models. Bump cautiously. |
| `THREADS` | `4` | Match logical core count (i7-7600U = 2c/4t). |

## Gaps vs. the Apple Silicon path

- No Metal — `-ngl 99` is meaningless; default is `-ngl 0`.
- No `-fa on` — flash-attention's CPU implementation is currently absent for these models; the flag is dropped from the CPU serve scripts.
- Smaller context windows (16384 vs. 131072) — KV cache scales linearly with `CTX` and dominates RSS on small-weight models.
- Smaller models — no GLM-4.5-Air, no Qwen3-Coder-Next-80B, no Kimi family. They don't fit.

## Optional: Vulkan iGPU path

Not validated. The repo's apt `llama.cpp` package is CPU-only. To try partial offload to HD 620:

1. Build llama.cpp from source with `-DGGML_VULKAN=ON`.
2. Re-run `qwen3-4b-serve` with `NGL=20` and `NGL=99`.
3. Worth it only if decode improves ≥ 30%. HD 620 has 24 EUs and shares system RAM — the speedup is often marginal.

See TODO §6 in `docs/TODO_x270.md`.

## Troubleshooting

- `qwen3-4b-serve` fails with `error: model not found` → run `install/qwen3-4b.sh` first.
- `tool-call-test` FAILs with `content` showing a markdown JSON block → the chat-template override didn't load. Check `ps -p <llama-server-pid> -o args=` for `--chat-template-file` and that the file at that path is non-empty.
- `pi --model <id>` says `Model "..." not found` even though `config/models.json` has it → `~/.pi/agent/models.json` should be a symlink into the repo (see `install/base.sh`). Verify with `ls -l ~/.pi/agent/models.json`; if it's a real file, re-run `./install/base.sh` to convert. `pi --list-models` is the authoritative view of what pi sees.
- llama-server exits immediately after `~/bin/qwen3-4b-serve &` from a Claude Code session → use `nohup ... &; disown` or run it in a real terminal. Job-control shells SIGHUP background children on parent exit.
- Decode dips below ~3 tok/s sustained → CPU thermal throttling. The X270's 15W TDP and 2c/4t means the CPU sustains its 2.8 GHz base only briefly; check `watch -n1 'cat /proc/cpuinfo | grep MHz'`.
