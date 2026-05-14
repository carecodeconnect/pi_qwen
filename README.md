# pi_sandbox

A sandbox for running [pi](https://pi.dev) — a minimal terminal coding agent — against **local** models on Apple Silicon. Swap models, swap inference engines, A/B them on your own hardware. No API keys. No cloud round-trips. All inference on your machine.

The documented default is [Qwen3-Coder-30B-A3B-Instruct](https://huggingface.co/Qwen/Qwen3-Coder-30B-A3B-Instruct) via [llama.cpp](https://github.com/ggml-org/llama.cpp), with wired-up alternates for [Qwen3-Coder-Next-80B](https://huggingface.co/Qwen/Qwen3-Next-80B-A3B-Instruct), [gpt-oss-20b](https://huggingface.co/openai/gpt-oss-20b), and [GLM-4.5-Air](https://huggingface.co/zai-org/GLM-4.5-Air). See [docs/02-models.md](docs/02-models.md) for the trade-offs and what didn't work.

![pi + Qwen3-Coder demo](demo/pi-qwen.gif)

## Why this stack

- **Local models on Apple Silicon are practical now.** A modern MoE in Q5 quant (~12–20 GB) runs at 50–60 tok/s decode on an M1 Max with no cloud round-trip. Coding-agent latency is workable; cost is electricity.
- **pi is an OpenAI-API-compatible coding agent**, so it talks to a local inference server (llama.cpp, mistral.rs, vLLM, …) the same way it talks to any cloud provider. Drop-in by design.
- **llama.cpp** has the most mature Metal backend and ships precompiled via Homebrew — no Xcode required. The repo also has scaffolding to swap in [mistral.rs](docs/07-engines.md) as a Rust-native alternative.
- **Sandbox by intent.** The scripts and configs make it cheap to try a new model: download a GGUF, drop in a serve wrapper, add a `models.json` entry, run `tool-call-test`. The [Tested and rejected](docs/02-models.md#tested-and-rejected) section is what that workflow's failure cases look like in practice.

## Tested on

- Apple M1 Max, 64 GB RAM, macOS 26.3 (`arm64`)
- llama.cpp via Homebrew (`b9100`)
- pi `0.74.0`
- Quant: `Qwen3-Coder-30B-A3B-Instruct-Q5_K_M.gguf` (~21 GB on disk, ~37 GB resident with the default 131 k context)

Measured throughput on this hardware (M1 Max, llama.cpp `b9100`, `-fa 1 -ngl 99 -r 3`):

| test                | Qwen3-Coder-30B-A3B<br>(Q5_K_M, 20 GiB) | Qwen3-Coder-Next-80B-A3B<br>(Q3_K_M, 36 GiB) | gpt-oss-20b<br>(MXFP4, 11 GiB) | GLM-4.5-Air<br>(UD-Q3_K_XL, 51 GiB) |
| ------------------- | --------------------------------------: | -------------------------------------------: | -----------------------------: | ----------------------------------: |
| pp512 (prefill)     |                          593.80 ± 4.38 |                               407.39 ± 0.89 |                **755.59 ± 0.90** |                       160.62 ± 1.25 |
| pp2048              |                          554.40 ± 0.51 |                               398.95 ± 3.05 |                **741.53 ± 1.33** |                       150.45 ± 1.76 |
| pp8192              |                          409.13 ± 7.86 |                               381.04 ± 1.87 |                **650.61 ± 7.65** |                       116.98 ± 0.47 |
| tg128 (decode)      |                           50.76 ± 0.21 |                                31.93 ± 0.10 |                 **59.67 ± 0.46** |                        20.57 ± 0.08 |
| tg512               |                           50.00 ± 0.11 |                                31.94 ± 0.26 |                 **60.40 ± 0.31** |                        19.82 ± 0.30 |
| pp8192+tg128        |                          356.51 ± 2.71 |                               323.00 ± 2.03 |                **544.15 ± 3.87** |                       104.77 ± 1.50 |

See [docs/05-benchmarking.md](docs/05-benchmarking.md) for raw output, sweep parameters, and a full "reading the numbers" breakdown.

Should work on any Apple Silicon Mac with ≥ 32 GB RAM. Bigger context windows or higher-bit quants need more.

## How the pieces fit

```
┌─────────┐    HTTP /v1/chat/completions   ┌──────────────┐    Metal    ┌──────────┐
│   pi    │ ──────────────────────────────▶│ llama-server │ ──────────▶ │   GPU    │
│ (agent) │                                │  (llama.cpp) │             │ (M-chip) │
└─────────┘                                └──────────────┘             └──────────┘
                                                  ▲
                                                  │ reads
                                                  ▼
                                         ~/models/...Q5_K_M.gguf
```

pi sees an OpenAI-compatible endpoint. llama-server does the actual inference on Metal. Your model file sits on disk and is memory-mapped at load time.

## Daily use

Two commands in two terminals:

```bash
# Terminal 1 — start the server (leave it running)
qwen-serve

# Terminal 2 — drop into pi against the local model
cd /path/to/your/project
pi --model qwen3-coder-30b-a3b
```

Exit pi with `/exit` or Ctrl-D. The server keeps running across pi sessions; stop it with Ctrl-C or `serve-stop`. Switch models with `serve-stop` then a different `*-serve`.

## Docs

- **[01 — Quickstart](docs/01-quickstart.md)** — install llama.cpp + pi + uv, download the default model, first run.
- **[02 — Models](docs/02-models.md)** — the four working candidates, tested-and-rejected, next trials, choosing a quant.
- **[03 — Serving](docs/03-serving.md)** — the `*-serve` scripts and helpers (`qwen-test`, `tool-call-test`, `serve-stop`, `fetch-template`).
- **[04 — Tool calling](docs/04-tool-calling.md)** — chat-template fix, verification flow, `pi-web-access` extension, future MCP for git/GitHub.
- **[05 — Benchmarking](docs/05-benchmarking.md)** — `llama-bench` sweeps, raw output for all four models, reading the numbers.
- **[06 — Troubleshooting](docs/06-troubleshooting.md)** — common failure modes (slow downloads, npm permissions, OOM at load, Metal wired-memory cap, template bugs).
- **[07 — Alternative engines](docs/07-engines.md)** — mistral.rs (primary alternate), candle-vllm, Crane, vllm-mlx.
- **[08 — Recording the demo](docs/08-demo.md)** — `vhs` script for the README GIF.
- **[09 — Skills](docs/09-skills.md)** — what a skill is, where pi looks for them, adding project-local and global skills, reusing Claude Code / Codex skills.
- **[10 — Extensions](docs/10-extensions.md)** — TypeScript extensions, install patterns, what's wired into this repo (`pi-web-access` + the `pi-hooks` bundle), writing your own, skill vs. extension recap.
- **[11 — Prompt engineering](docs/11-prompt-engineering.md)** — evidence-based prompt tips per local model, reasoning levels, prompting via skills and extensions, empirical findings from this sandbox.

## Layout of this repo

```
pi_sandbox/
├── README.md           # this file — summary + docs index
├── LICENSE             # MIT
├── docs/               # detailed docs, one per stage
│   ├── 01-quickstart.md
│   ├── 02-models.md
│   ├── 03-serving.md
│   ├── 04-tool-calling.md
│   ├── 05-benchmarking.md
│   ├── 06-troubleshooting.md
│   ├── 07-engines.md
│   ├── 08-demo.md
│   ├── 09-skills.md
│   ├── 10-extensions.md
│   └── 11-prompt-engineering.md
├── install/            # one-shot install scripts (idempotent)
│   ├── base.sh                    # copies scripts + models.json into place
│   ├── qwen3-coder-30b.sh         # default coder model, ~21 GB
│   ├── qwen3-coder-next-80b.sh    # long-context coder, ~38 GB
│   ├── gpt-oss-20b.sh             # fastest, generalist, ~12 GB
│   ├── glm-4.5-air.sh             # largest, agent-tuned, ~55 GB
│   └── all-models.sh              # base + all four models in sequence
├── scripts/
│   ├── qwen-serve      # start llama-server for Qwen3-Coder-30B-A3B
│   ├── qwennext-serve  # alternate: Qwen3-Coder-Next-80B-A3B
│   ├── gptoss-serve    # alternate: OpenAI gpt-oss-20b
│   ├── glmair-serve    # alternate: Z.ai GLM-4.5-Air
│   ├── serve-stop      # kill whatever llama-server is on port 8080
│   ├── qwen-test       # one-shot chat-completion smoke test
│   ├── tool-call-test  # model-agnostic check that pi-style tool_calls fire
│   └── fetch-template  # fetch Qwen's official chat template (fixes tool calls)
├── bench/
│   └── throughput.sh   # llama-bench wrapper for pp/tg tok/s
├── demo/
│   ├── pi-qwen.tape    # vhs script for the README demo
│   └── smoke.tape      # minimal vhs script to verify the toolchain
└── config/
    └── models.json     # pi provider config (copy to ~/.pi/agent/)
```

## Credits

- [Qwen team](https://qwenlm.github.io/) for the base model
- [Unsloth](https://huggingface.co/unsloth) for the GGUF quants used here
- [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) for the inference engine
- [pi](https://pi.dev) for the agent

## Further reading

Three upstream catalogs that source the skills and extensions referenced in [docs/09-skills.md](docs/09-skills.md):

- [anthropics/skills](https://github.com/anthropics/skills) — Anthropic's official skills (docx, pdf, mcp-builder, skill-creator, frontend-design, …).
- [badlogic/pi-skills](https://github.com/badlogic/pi-skills) — community pi skills (brave-search, browser-tools, Google APIs, transcribe, vscode, youtube-transcript).
- [qualisero/awesome-pi-agent](https://github.com/qualisero/awesome-pi-agent) — meta-catalog of pi extensions, skills, tools, and prompt templates across the ecosystem.

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgments

This README was co-written by Claude Code and the Qwen3-Coder-30B-A3B model with Pi.
