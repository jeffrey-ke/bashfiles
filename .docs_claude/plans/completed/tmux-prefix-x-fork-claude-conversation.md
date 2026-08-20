# prefix+X: fork the Claude conversation in this pane into a sibling pane

## Context

`claude-skills/fork-conversation-pane/` already did the hard part — it knows every
guard needed to spawn `claude --resume <id> --fork-session` into a tmux pane. But
reaching it meant *asking Claude to fork*, and the model round trip is the slow part:
the split itself is one `tmux split-window`. The ask was to turn the skill into a plain
key binding, with the suggested mechanism being "rename the pane to the conversation id,
then have the script read the name back".

That mechanism turns out to be unnecessary, and would not have worked anyway: Claude
Code overwrites the pane title with its own conversation summary seconds after startup
(already recorded as guard 8 in the skill).

## The lookup that makes it possible

Claude Code (verified on **2.1.235**) already publishes the index this needs.
`~/.claude/sessions/<pid>.json`, one file per running process:

```json
{"pid":2343498,"sessionId":"cc28879b-...","cwd":"/home/jke/dotfiles",
 "procStart":"36396463","entrypoint":"cli","tmux":"claude:@13.%28","name":"dotfiles-e9"}
```

`tmux` is `<session>:@<window>.%<pane>`, so **pane → conversation is a pure file
lookup**. No pane renaming, no `SessionStart` hook stamping a `@claude_session_id` pane
option, and no need for the skill's "newest `*.jsonl` in the project dir" fallback —
which guesses wrong whenever two Claudes share a directory, the normal case here.

Nothing else works as a substitute. The claude process's own `/proc/<pid>/environ` has
**no** `CLAUDE_CODE_SESSION_ID` (it is generated after exec and only injected into
children), and the process keeps no transcript fd open, so there is nothing to scrape.

## What gets touched

| File | Change |
|---|---|
| `tmux-fork-claude.sh` | **new** — resolves pane → session, delegates to the skill's `fork-pane.sh` |
| `.tmux.conf` | `prefix+X` (pane) and `prefix+C-x` (window) bindings |
| `claude-skills/fork-conversation-pane/fork-pane.sh` | now passes `--name` and `--append-system-prompt`, matching in-app `/branch`; new `-n` / `-A` |
| `claude-skills/fork-conversation-pane/SKILL.md` | points at the key binding for bare forks; keeps the skill for seeded/worktree/model cases |
| `.docs_claude/notes/claude-session-tmux-pane-lookup.md` | **new** — the lookup and its traps |
| `CLAUDE.md` | tmux-conventions paragraph + notes-table row |

The resolver deliberately delegates rather than reimplementing: every guard
(`exec` in the split command, `-P -F '#{pane_id}'` instead of diffing `list-panes`,
`remain-on-exit` while starting, the 30s readiness poll) stays in `fork-pane.sh`, so the
skill path and the key path cannot drift apart. It passes the pane through
`TMUX_PANE`, which is exactly the input `fork-pane.sh` already resolves its target
window from.

## The four traps, all found empirically

1. **Filter on `entrypoint`, not `kind`.** A headless `claude -p` also records
   `kind:"interactive"`, and it inherits `TMUX_PANE` from whoever launched it — so a
   `claude -p` fired from a Bash tool call writes a record claiming *the user's pane*
   with a **newer** `startedAt` than the real session. Only `entrypoint` separates them
   (`"cli"` vs `"sdk-cli"`). Confirmed by holding a live one-shot open in the same pane
   and checking that the lookup still picked the interactive session. Preferring a
   descendant of the pane's shell does **not** disambiguate — the one-shot is one too.
2. **`run-shell` does not set `TMUX_PANE`.** It *does* format-expand `#{pane_id}` in the
   command string (tmux 3.4), so the pane must be passed as an argument — the same
   reason `bind-key e` already does. Claude's Bash tool *does* export `TMUX_PANE`, so
   code that works when Claude runs it silently retargets the attached client's pane
   when a key binding runs it.
3. **The session records have no trailing newline**, so `IFS= read -r j < "$f"` exits
   **1** while still setting `$j`. This bit twice: first as a `|| continue` that skipped
   every file and found nothing, then — after being written up as a trap — again in
   `fork-pane.sh`, which unlike the resolver runs under `set -e`, where the same read
   aborted the whole script with exit 1. It needs `|| true` there.
4. **macOS has no `/proc`.** Liveness and the parent walk fall back to `kill -0` and
   `ps -o ppid=`; `procStart` cannot be compared there. `FORK_CLAUDE_NO_PROC=1` forces
   that path on Linux, and both paths were checked to agree across every live pane.

## Matching what in-app `/branch` gives a fork

First cut spawned a fork with no name and no idea it was a fork — the user noticed
immediately, because `/branch` produces both. Reading the 2.1.235 bundle explains it:
`/branch` (`"Create a branch of the current conversation at this point"`) is a different
code path that pre-generates the session id, snapshots the transcript, force-flushes the
parent (refusing with *"Couldn't fork — this conversation is still being saved"* if the
flush doesn't land), and then spawns a **background job** — the roster behind the
`← for agents` hint — not a tmux pane. On the way it adds:

- `--name "<parent> ⑂ <what>"` — `⑂` is U+2442 OCR FORK
- `--append-system-prompt` with *"This conversation was forked from a session that is
  still working in this checkout (…). Before making code changes, create a new worktree
  of your own with EnterWorktree so your edits don't land where the original session is
  editing."* — emitted only when the fork shares the parent's live checkout
- `--model` / `--effort` / `--permission-mode` / `--add-dir` / `--allowed-tools`
- job-registry lineage: `forkSourceAlive`, `forkBoundaryAt`, `forkSessionId`,
  `forkParentSessionId`

The first two are plain CLI flags, so `fork-pane.sh` now passes both, deriving the
parent's name from the same `sessions/<pid>.json` record and emitting the notice only
when the fork's cwd equals the still-live parent's. Verified by reading the spawned
fork's own `/proc/<pid>/cmdline`.

The lineage is **not** reproducible for a pane fork. It is carried by
`CLAUDE_CODE_RESUME_SOURCE_ALIVE` (`sessionId|<ISO timestamp>|parentSessionId`), whose
*lineage fields* are only written when `CLAUDE_JOB_DIR` is set — i.e. for job-managed
background sessions. A pane fork is not a job, so it will never appear in the roster as
a branch of its parent. That env var has two other effects that are **not** job-gated,
though, and a later pass turned both on for pane forks — see "Bounding the fork's
orphaned-task scan" below.
This also dates guard 8 in the skill ("nothing on disk records the lineage"): still true
of the CLI path, but the in-app path does record it, in the job registry rather than the
transcript.

## Bounding the fork's orphaned-task scan (follow-up)

Forking left the fork announcing every background task the parent had ever left
unfinished: *"No completion record was found for this background shell command from the
previous session."* The resume-time orphan scan reads the **replayed** transcript, and a
fork replays all of it, so the fork reports shells, Monitors, agents and workflows it
does not own — a `tail -F` Monitor every time, since it can never produce a completion
record.

Setting `CLAUDE_CODE_RESUME_SOURCE_ALIVE` to `<fork sid>|<ISO boundary>|<parent sid>`
confines that scan to messages newer than the boundary. Reading 2.1.236, this is not
job-gated (unlike the lineage fields) — it is parsed on every resume. Naming the fork's
session id up front, which `--session-id` permits precisely because `--fork-session` is
also set, additionally earns the fork the genuine `/branch` note: *"began as a fork
(copy) of another session that is still running…"*, emitted only while the parent lives.
A/B on a session holding one orphaned Monitor: **2** notices without the var, **0** with
it, plus the fork note. The only thing given up is the copy of the parent's file-history
backups into the fork, so `/rewind` there stops at the boundary;
`FORK_CLAUDE_NO_BOUNDARY=1` restores the old behaviour.

## Key changes

- `tmux-fork-claude.sh` maps a tmux pane to the Claude session running in it via
  `~/.claude/sessions/<pid>.json`, filtering to `entrypoint:"cli"`, verifying the pid
  against `procStart`, and preferring a descendant of the pane's shell; `--resolve`
  prints the decision, since a `run-shell -b` child's output is shown nowhere.
- `prefix+X` forks into a sibling pane, `prefix+C-x` into a new window; `prefix+x`
  (kill-pane) still undoes it. Both were unbound before.
- All user-visible messages go through `tmux display-message` for the same reason.
- `fork-pane.sh` gained `--name`/`--append-system-prompt` parity with `/branch`, plus
  `-n NAME` and `-A` (suppress the notice), and reports the derived name.
- No install step: the script is referenced by absolute `$HOME/dotfiles` path like the
  other `tmux-*.sh` helpers, and `.tmux.conf` is already symlinked.
- `fork-pane.sh` sets `CLAUDE_CODE_RESUME_SOURCE_ALIVE` and `--session-id` so the fork
  reports only its own orphaned tasks, not the parent's, and gets the real `/branch`
  fork note; `FORK_CLAUDE_NO_BOUNDARY=1` opts out.
