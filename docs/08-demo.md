# Recording the demo

The GIF at the top of the README is generated with [vhs](https://github.com/charmbracelet/vhs) — a scripted terminal recorder. The tape lives in [`demo/pi-qwen.tape`](../demo/pi-qwen.tape), so re-running it after a change is one command instead of "perform the demo perfectly again."

## Prerequisites

```bash
brew install vhs ttyd ffmpeg
```

`vhs` drives the recording, `ttyd` is the PTY web bridge it talks to, `ffmpeg` does the encode. All three must be on PATH.

## How a recording works

vhs spawns a headless Chrome that connects to a `ttyd`-hosted shell. It executes the `.tape` script keystroke-by-keystroke, screenshots each frame, and renders to the file named in the `Output` directive. **vhs does not start `qwen-serve`** — start it in a separate terminal first, otherwise pi will fail to connect and the recording will end early with `context canceled`.

## Record

```bash
qwen-serve                              # terminal 1
vhs demo/pi-qwen.tape                   # terminal 2
```

Output lands at `demo/pi-qwen.gif`.

## Iterate

`vhs serve` opens a local WebSocket preview — the tape re-renders on save, so you can tune `Sleep` durations and styling without burning a full render each time:

```bash
vhs serve
# edit demo/pi-qwen.tape in your editor; preview updates on save
```

## What the directives do

| Directive | What it controls |
|---|---|
| `Output demo/pi-qwen.gif` | Output path. Swap to `.mp4` or `.webm` for smaller files. |
| `Set FontSize 14` | Render size of glyphs. |
| `Set Width 1400 / Height 800` | Canvas in px. Bigger = sharper but heavier. |
| `Set Theme "..."` | One of vhs's bundled themes. |
| `Set TypingSpeed 50ms` | Per-keystroke delay for `Type`. |
| `Set PlaybackSpeed 1.5` | Speeds up the final video; useful when decode is slow. |
| `Hide ... Show` | Run commands without recording (great for `cd` + `clear`). |
| `Type "..."` | Types a string. |
| `Enter` | Submits. |
| `Sleep 60s` | Waits — vhs has no "wait for output" primitive, so you size this empirically. |

## GIF vs MP4

A 60-second decode at 1400×800 produces an **8–20 MB GIF**, which is close to GitHub's README image limit. If it bloats, change one line:

```
Output demo/pi-qwen.mp4
```

and embed in the README with `<video src="demo/pi-qwen.mp4" controls></video>`. GitHub renders it inline at roughly 1/10th the size.
