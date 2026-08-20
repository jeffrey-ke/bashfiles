# Resolving a tmux pane to the Claude session running in it

How `tmux-fork-claude.sh` (bound to `prefix+X`) knows which conversation to fork,
without any help from the Claude process it is forking, and how the fork is stopped
from inheriting the parent's orphaned background tasks. All verified on Claude Code
**2.1.235** (**2.1.236** for the orphan-scan section) / tmux 3.4 / Linux.

## The index already exists: `~/.claude/sessions/<pid>.json`

Claude Code writes one file per running process, keyed by **pid**, and it contains
both halves of the mapping:

```json
{"pid":2343498,"sessionId":"cc28879b-...","cwd":"/home/jke/dotfiles",
 "startedAt":1787095184448,"procStart":"36396463","version":"2.1.235",
 "kind":"interactive","entrypoint":"cli","tmux":"claude:@13.%28",
 "name":"dotfiles-e9","status":"busy","updatedAt":...}
```

`tmux` is `<session>:@<window>.%<pane>`, so pane → `sessionId` is a plain lookup.
Claude Code removes the file when the process exits (confirmed: a headless run's file
disappeared on exit), so stale entries are rare — but `procStart` is exactly
`/proc/<pid>/stat` field 22, so a recycled pid is still cheap to rule out.

Consequences: **no SessionStart hook is needed** to stamp the pane, and the
"newest `*.jsonl` in the project dir" fallback (guard 1 in the
`fork-conversation-pane` skill) is never needed either — that guess picks the wrong
session whenever two Claudes share a directory, which is the normal case here.

## The traps

1. **Filter on `entrypoint`, not `kind`.** A headless `claude -p` also records
   `kind:"interactive"`, and it inherits `TMUX_PANE` from whoever launched it — so a
   `claude -p` fired from a Bash tool call writes a file claiming *the user's pane*,
   with a **newer** `startedAt` than the real session. Only `entrypoint` separates
   them: `"cli"` for a real interactive Claude, `"sdk-cli"` for the one-shot. Without
   this filter `prefix+X` intermittently forks a throwaway. Being a descendant of the
   pane's shell does *not* disambiguate — the one-shot is one too.
2. **`run-shell` does not set `TMUX_PANE`.** It *does* format-expand `#{pane_id}` in
   the command string (tmux 3.4), so the pane must be passed as an argument — the same
   reason `bind-key e` does it. Claude's Bash tool *does* export `TMUX_PANE`, so code
   that works when Claude runs it silently targets the attached client's pane when a
   key binding runs it.
3. **The session files have no trailing newline.** `IFS= read -r j < "$f"` therefore
   exits **1** while still setting `$j`; a `|| continue` on it skips every file and the
   lookup finds nothing. Test emptiness, not the read's status — and under `set -e`
   (which `fork-pane.sh` uses, unlike the resolver) that read *aborts the script* with
   exit 1 unless it is written `|| true`.
4. **Nothing can be scraped from the claude process itself.** `/proc/<pid>/environ`
   has no `CLAUDE_CODE_SESSION_ID` (it is generated after exec and only injected into
   children), and the process keeps no transcript fd open.
5. **The pane title is not usable storage.** Claude Code overwrites it with its own
   conversation summary seconds after startup. (A tmux user option such as
   `@claude_session_id` would survive — it just isn't needed given the index above.)
6. **macOS has no `/proc`.** Liveness and the parent walk fall back to `kill -0` and
   `ps -o ppid=`; `procStart` cannot be compared there. `FORK_CLAUDE_NO_PROC=1`
   forces that path for testing on Linux.

## A fork inherits the parent's orphaned background tasks

`--fork-session` replays the parent's transcript, and Claude Code's resume-time
orphan scan reads that replay: every background shell, Monitor, agent and workflow
recorded in it that has no completion record is reported as
*"No completion record was found for this background shell command from the previous
session."* The fork owns none of them. A `tail -F` Monitor is the worst case — it
can never exit, so it never has a completion record.

The scan is bounded by `CLAUDE_CODE_RESUME_SOURCE_ALIVE`, formatted
`<fork session id>|<ISO boundary>|<parent session id>` (2.1.236). When it parses,
the scan only looks at messages whose timestamp is **after** the boundary — i.e.
only what the fork itself produced. `fork-pane.sh` sets it, with a fresh UUID also
passed as `--session-id`, which is accepted alongside `--resume` **only** when
`--fork-session` is set too:

    Error: --session-id can only be used with --continue or --resume if
    --fork-session is also specified.

Measured, forking a session holding one orphaned Monitor: **2** such notices
without the var, **0** with it. Naming the fork's session id up front also earns it
the real `/branch` note (*"began as a fork (copy) of another session that is still
running: a session whose self-reported name is …"*), which only fires while the
parent is still alive. Leaving the first field empty still applies the boundary,
just without that note.

Two further consequences, both arguably wanted: the fork no longer re-resurrects
the parent's session crons or auto-resumes its background agents (otherwise parent
and fork both would), and the parent's file-history backups are **not** copied into
the fork, so `/rewind` there cannot reach pre-boundary checkpoints. That copy is the
only thing given up; `FORK_CLAUDE_NO_BOUNDARY=1` opts out.

Note that the notice is self-suppressing *within* one transcript — a task id that
already appears in a `<task-notification>` is skipped — so a session that has
already reported an orphan will not report it twice. That makes such a session
useless as a test subject; test against one where the task was launched but never
reported.

## A pane fork is not what `/branch` makes

`/branch` spawns a **background job** (the roster behind the `← for agents` hint), not a
tmux pane, and on the way it adds a `--name "<parent> ⑂ …"`, an `--append-system-prompt`
fork notice, and job-registry lineage (`forkParentSessionId` and friends, carried by
`CLAUDE_CODE_RESUME_SOURCE_ALIVE` and only read when `CLAUDE_JOB_DIR` is set). The first
two are plain CLI flags and `fork-pane.sh` now passes them; the lineage is unreachable
for an interactive pane, so `prefix+X` forks never show up in the roster as branches.
(`CLAUDE_CODE_RESUME_SOURCE_ALIVE` itself is only job-gated for the *lineage fields*
— its boundary filter and fork note are read on every resume. See above.)
Full anatomy in `.docs_claude/plans/completed/tmux-prefix-x-fork-claude-conversation.md`.

## Debugging

`tmux-fork-claude.sh %28 --resolve` prints the resolved session, cwd and whether the
pid is in the pane's process subtree. Needed because a `run-shell -b` child's stdout
and stderr are shown nowhere — every user-visible message in that script goes through
`tmux display-message`.
