---
name: swap-model
description: Switch the local llama-server pi is talking to between Qwen3-Coder-30B, Qwen3-Coder-Next-80B, gpt-oss-20b, and GLM-4.5-Air. Use when the user asks to swap, switch, change, or try a different local model, or mentions starting/stopping serve scripts. Only one model can hold port 8080 at a time, so the previous server must be stopped first. Walks through serve-stop, the right *-serve, optional tool-call verification, and the pi --model alias to drop into.
---

# Swap local model

Switches which local model pi is talking to. Only one llama-server can hold port 8080 at a time, so swapping is: stop current → start target → (optional) verify → re-launch pi against the new alias.

## Model → serve script → pi alias map

| Model | Serve script | Pi `--model` alias | Notes |
|---|---|---|---|
| Qwen3-Coder-30B-A3B | `qwen-serve` | `qwen3-coder-30b-a3b` | Default. ~20 GiB, ~51 tok/s decode. |
| Qwen3-Coder-Next-80B-A3B | `qwennext-serve` | `local-qwen3-coder-next` | Long-context winner. ~36 GiB, ~32 tok/s. |
| gpt-oss-20b | `gptoss-serve` | `local-gpt-oss-20b` | Fastest. ~11 GiB, ~60 tok/s. |
| GLM-4.5-Air | `glmair-serve` | `local-glm-4.5-air` | Slowest. ~51 GiB, ~20 tok/s. **Needs wired-memory bump — see below.** |

## Preflight: are you about to disconnect yourself?

**This skill can only be driven by a model that is not the one being swapped from.** Step 2 kills the llama-server on port 8080. If that server is hosting *you*, you will lose the connection mid-procedure and the swap will half-complete (old server stopped, new server never started).

Before doing anything else, identify the currently running local model:

```bash
curl -s http://127.0.0.1:8080/props | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('model_path','(unknown)'))"
```

Compare the returned path against the user's "swap from" model:

- `.../qwen3-coder-30b-a3b/...` → driven by `qwen3-coder-30b-a3b`
- `.../qwen3-coder-next/...` → driven by `local-qwen3-coder-next`
- `.../gpt-oss-20b/...` → driven by `local-gpt-oss-20b`
- `.../glm-4.5-air/...` → driven by `local-glm-4.5-air`

If the running model matches the swap-*from* target, **abort the procedure**. Tell the user:

> "I'm running on the model you're asking me to swap away from, so I can't drive this swap — `serve-stop` would disconnect me before I could start the new server. Please run the swap manually:
> ```
> serve-stop
> <target-serve> > /tmp/llama-server.log 2>&1 &
> until curl -sf http://127.0.0.1:8080/health > /dev/null; do sleep 2; done
> ALIAS=<pi-alias> tool-call-test
> ```
> Then exit pi (Ctrl-D) and re-launch with `pi --model <pi-alias>`. Or drive this skill from a non-local model (Claude Code, Codex, etc.) that doesn't depend on port 8080."

Only continue to step 1 if the running model is *different* from the swap-from target (i.e., you're driving the swap from a model that won't be killed by `serve-stop`).

## Procedure

1. **Identify the target model** from the user's request. Match against the table above. If ambiguous, ask.

2. **Stop the current server** (idempotent — no-op if nothing is listening):

   ```bash
   serve-stop
   ```

3. **GLM-4.5-Air only — check the Metal wired-memory cap.** GLM needs at least 49152 MB. If lower, the user must run `sudo sysctl iogpu.wired_limit_mb=57344` themselves before continuing (sudo is needed):

   ```bash
   sysctl iogpu.wired_limit_mb
   ```

   Skip this step for any other model.

4. **Start the target server** in the background so the rest of the procedure can continue. The server prints `main: server is listening on http://127.0.0.1:8080` when ready:

   ```bash
   <target-serve> > /tmp/llama-server.log 2>&1 &
   ```

   Where `<target-serve>` is one of `qwen-serve` / `qwennext-serve` / `gptoss-serve` / `glmair-serve` from the table.

5. **Wait for the server to finish loading.** Poll the `/health` endpoint until it returns 200 (GLM-Air can take 30–90 s to mmap 51 GB; the others are faster):

   ```bash
   until curl -sf http://127.0.0.1:8080/health > /dev/null; do sleep 2; done
   ```

6. **Verify structured tool calls fire** (recommended, especially for an untested model — this is the gate that caught DeepSeek-Coder-V2-Lite):

   ```bash
   ALIAS=<pi-alias> tool-call-test
   ```

   Expect `PASS: structured tool_calls returned`. If it fails, do not proceed to step 7 — surface the failure to the user.

7. **Tell the user the swap is done** and give them the command to launch pi in their own terminal (the model can't drive interactive pi from inside a session):

   ```
   pi --model <pi-alias>
   ```

## Failure modes

- **`serve-stop` reports nothing on port 8080** — fine, just means no server was running. Continue.
- **`tool-call-test` returns 503** — server hasn't finished loading. Wait longer (loop on `/health`).
- **`tool-call-test` returns text instead of structured tool_calls** — chat template bug, see `docs/04-tool-calling.md`. Stop and surface this to the user; don't try to "fix" it from inside the skill.
- **GLM-Air returns HTTP 500 with `kIOGPUCommandBufferCallbackErrorOutOfMemory`** — wired-memory cap is too low. See `docs/06-troubleshooting.md`. User needs to raise it with sudo and restart `glmair-serve`.
- **Port 8080 already in use** — another `*-serve` is running. Run `serve-stop` again, or `lsof -i :8080` to find what's holding it.
- **`Error: Connection error.` immediately after `serve-stop`** — you skipped the preflight. The model driving this skill was the one being swapped from, and step 2 killed the server hosting it. The swap is now half-done (old server stopped, new server not started). The user must finish manually per the preflight's instructions.
