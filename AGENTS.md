# Agent guidelines for this project

You have a `bash` tool — use it freely for shell operations including git
(`git add`, `git commit`, `git push`), file management, and process control.
Do not refuse or disclaim shell capability; if a command needs user
confirmation, pi will prompt the user — that's not your concern.

For destructive commands (`rm -rf`, force-push, branch deletion, history
rewrites), confirm with the user first. Otherwise just run the command.
