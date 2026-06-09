# Agent guidelines for this project

You have a `bash` tool — use it freely for shell operations including git
(`git add`, `git commit`, `git push`), file management, and process control.
Do not refuse or disclaim shell capability; if a command needs user
confirmation, pi will prompt the user — that's not your concern.

For destructive commands (`rm -rf`, force-push, branch deletion, history
rewrites), confirm with the user first. Otherwise just run the command.

## Tool use (matters most for small local models, e.g. on the P53)

Only call tools when the task needs them; answer greetings directly. Treat tool
output as ground truth — never answer from training memory when a tool returned
data.

When asked to create, modify, or run something, **actually call** the `write` /
`edit` / `bash` tools — do not print a tool call as a text/JSON code block or
describe what you "would" do. Act, don't narrate.
