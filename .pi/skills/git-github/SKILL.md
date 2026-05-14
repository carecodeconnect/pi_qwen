---
name: git-github
description: Commit, push, and create GitHub pull requests for this repo. Use when the user asks to commit changes, push to a branch, open a PR, or describe what's changed on the current branch. Encodes this repo's commit-message style (terse present-tense, no conventional-commit prefixes), safe staging (no `git add -A`/`git add .`), secret detection before commit, and the `gh pr create` HEREDOC pattern for PR bodies. Includes safety preflight: never force-push to main, never `--no-verify`, never commit without explicit user ask.
---

# Git + GitHub workflow

Procedures for committing, pushing, and opening pull requests in this repo. Uses pi's built-in `bash` tool — no new tools needed.

## Safety rules (always)

1. **Never commit unless the user explicitly asked.** Reviewing a diff, writing code, or staging are fine without explicit ask. Creating a commit is not.
2. **Never use `git add -A` or `git add .`** — they can pull in `.env`, credentials, large binaries, or in-progress files. Always stage by filename.
3. **Never `--no-verify`** to skip pre-commit hooks. If a hook fails, fix the underlying issue and create a new commit.
4. **Never force-push to `main`/`master`.** Warn the user if they ask. For feature branches, only force-push if the user explicitly asks.
5. **Never amend a commit that has been pushed** unless the user explicitly asks. Prefer a new commit.
6. **Never `git reset --hard`, `git checkout .`, `git clean -f`, or `git branch -D`** without explicit ask — these are destructive and silently throw away work.

## Procedure A: commit + push

### 1. Survey current state (parallel-safe)

Run these together to understand what's changing:

```bash
git status
git diff
git diff --staged
git log --oneline -5
```

From the diff, identify:
- **What changed and why** (one-sentence summary you'd give a teammate).
- **Whether any staged path looks sensitive**: `.env*`, `*credentials*`, `*secret*`, `*.pem`, `*.key`, anything with high-entropy strings in the diff. If yes, **stop and ask the user** before continuing.
- **Whether any path is large/binary** that shouldn't be in git: `*.gguf`, `*.safetensors`, `node_modules/`, `target/`. If yes, check `.gitignore` and surface the issue.

### 2. Match this repo's commit-message style

Look at `git log --oneline -10` to confirm the style. As of this repo's history, conventions are:

- **Subject**: imperative present tense ("Add", "Restructure", "Scaffold", "Retire", "Fix"). ~50–70 chars. No trailing period.
- **No conventional-commit prefixes** — no `feat:`, `fix:`, `chore:`, etc.
- **Body** (optional, blank line after subject): explains the *why* if non-obvious. Wrap at ~72 chars.
- **Co-Authored-By trailer** when AI-written:
  ```
  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  ```

Good examples from this repo:
- `Add install/ scripts for one-shot, idempotent model setup`
- `Restructure docs/ for stage-based navigation, add pi-web-access`
- `Add GLM-4.5-Air alternate, retire Devstral and DeepSeek-Coder-V2-Lite`

### 3. Stage explicitly + commit

Stage by filename (never `-A` / `.`):

```bash
git add path/one.md path/two.sh
```

Use a HEREDOC for the message so newlines and special characters survive:

```bash
git commit -m "$(cat <<'EOF'
Subject line in imperative present tense

Optional body explaining the why if non-obvious. One or two short
paragraphs is fine — don't write a novel.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

Then verify:

```bash
git status
git log --oneline -3
```

### 4. Pre-commit hook failure

If the commit fails because a pre-commit hook rejected it: the commit **did not happen**. Don't `--amend` — that would modify the *previous* commit. Instead:

1. Read the hook's output.
2. Fix the underlying issue.
3. Re-stage the fixed files.
4. Create a **new** commit (not an amend).

### 5. Push

```bash
git push
```

If pushing a brand-new branch:

```bash
git push -u origin <branch-name>
```

For `main`/`master`: only push if the user asked. Don't auto-push on every commit unless the user has said so.

## Procedure B: open a pull request

### 1. Survey what the PR will contain

Don't look at just the last commit — look at **all** commits since the branch diverged from `main`:

```bash
git status
git diff main...HEAD
git log main..HEAD --oneline
```

If the branch already tracks a remote and is behind, you may need to push first.

### 2. Draft title + body

- **Title**: under 70 chars. Same style as commit subjects (imperative present, no conventional-commit prefix). The title goes in the title; details go in the body.
- **Body** (markdown): two sections at minimum:
  ```markdown
  ## Summary
  - One to three bullets covering what changed and why.

  ## Test plan
  - [ ] Bulleted checklist of how to verify the PR.

  🤖 Generated with [Claude Code](https://claude.com/claude-code)
  ```
- Mention any breaking changes, migrations, or follow-up work explicitly.

### 3. Create the PR

Use a HEREDOC for the body so multi-line markdown stays intact:

```bash
gh pr create --title "the pr title" --body "$(cat <<'EOF'
## Summary
- Bullet 1
- Bullet 2

## Test plan
- [ ] Step 1
- [ ] Step 2

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Return the PR URL to the user when done.

## Other useful operations

- View PR comments: `gh api repos/<owner>/<repo>/pulls/<num>/comments`
- View CI status: `gh pr checks`
- View a PR: `gh pr view <num>`
- Compare branches: `git log main..HEAD --stat`

## Failure modes

- **`git commit` fails with "Author identity unknown"** — the repo's user.email/user.name isn't set. Surface to the user; don't run `git config` yourself (changing git config without explicit ask is out of scope).
- **`git push` rejected (non-fast-forward)** — remote has commits you don't. Run `git fetch && git log HEAD..@{u} --oneline` to see what. Don't force-push to resolve; discuss with the user.
- **`gh pr create` fails with auth error** — `gh auth status` to check. Surface to user; don't run `gh auth login` yourself (interactive).
- **Pre-commit hook fails** — see Procedure A step 4. Never `--no-verify` to bypass.
- **`git add` accidentally staged a secret** — `git restore --staged <file>` to un-stage *before* committing. If already committed but not pushed: `git reset --soft HEAD~1` then re-stage carefully. If already pushed: stop and tell the user — secret rotation is needed.
- **Branch is behind `main` and PR is requested** — surface to the user and ask whether to `git pull --rebase origin main` first (rebase) or `git merge origin/main` (merge commit). Don't pick for them.
