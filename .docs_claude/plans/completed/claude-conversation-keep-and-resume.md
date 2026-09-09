# Keeping Claude Code conversations: `prefix A` to name one, `prefix C-a` to find it

## Context

Claude Code transcripts are spread across `~/.claude/projects/<mangled-cwd>/`, named by
uuid, and on a deletion clock: `cleanupPeriodDays` defaults to 30 and is unset in
`~/.claude/settings.json`, so at the time of writing there were 129 transcripts on this
machine and **zero** older than 30 days — history was being silently deleted. Resuming a
specific old conversation meant remembering both a directory and a uuid.

The ask: a key binding that files the conversation running in this pane under a name I
choose, with a note on why it is worth keeping, plus a picker to find and reopen it.

An earlier design for this (its `PLANS_TOC.md` entry survived; the plan body itself was
never written or was lost) proposed a richer system: the archive would *own* the
transcript bytes and leave a **symlink** behind in `~/.claude/projects/`, so Claude's own
`/resume` picker kept working, plus a `ccrg` search wrapper that re-rendered JSONL hits
into readable turns. That design was rejected here — see below.

## Final solution

Five scripts in `bin/`, each doing one thing, composed by a pipe. Nothing is a symlink;
nothing is stored twice; there is no index file.

```
prefix A                                   prefix C-a
   |                                          |
   v                                          v
ccsave <pane-id>                           ccfind
   |  tmux-fork-claude.sh --resolve           |  lists $CC_ARCHIVE/*/meta.yaml
   |  -> session uuid + cwd                   |  fzf, preview, Enter
   |  popup editor: name + why                v
   v                                       ccresume <name>
ccpaths <uuid> | ccstash -w why -c cwd <name>  |  copies the transcript back to
                                               |  the recorded project_dir, then
                                               v  claude --resume <uuid>
```

**`ccpaths <uuid> [-a]`** — read-only. Prints the paths Claude keeps for a session, one
per line, and only those that exist, so consumers need no per-kind conditionals. Four
kinds exist; two are worth keeping:

| Path | Typical size | What it is | Archived? |
|---|---|---|---|
| `projects/<slug>/<uuid>.jsonl` | 30 KB – 1.2 MB | the conversation | yes |
| `projects/<slug>/<uuid>/` | ~550 KB | `tool-results/` + `subagents/*.jsonl` | yes |
| `file-history/<uuid>/` | ~150 KB | the `/rewind` store (file backups) | only with `-a` |
| `session-env/<uuid>/` | 0 | empty on every session in this corpus | never |

It *finds* the transcript by glob rather than computing the slug, because the slug is the
cwd with both `/` and `.` mapped to `-` (`/home/jke/.claude/sessions` →
`-home-jke--claude-sessions`) and does not round-trip. Two project dirs holding the same
uuid is an error, not a guess.

**`ccstash [-w WHY] [-c CWD] [-f] <name>`** — reads paths on stdin, copies them into
`$CC_ARCHIVE/<name>/` (default `~/conversations`). It takes a *name*, never a
destination, so there is no way to call it and get a stray folder somewhere. Result:

```
~/conversations/<name>/
├── meta.yaml            name, session, project_dir, cwd, saved, transcript, sidecar
├── why.md               your words — the thing you actually grep
├── first-prompt.txt     auto-extracted opening prompt, for the picker
├── <uuid>.jsonl         the conversation, original basename = the session id
└── <uuid>/              sidecar, if the session had one
```

**`ccsave [-f] [-a] [<pane-id>]`** — the wrapper. Resolves pane → uuid by shelling out to
`tmux-fork-claude.sh --resolve`, so the lookup's guards (`sdk-cli` filtering,
pid/`procStart` verification, the `/proc`-free macOS fallback) live in exactly one place.
Then a template in `$EDITOR`: line 1 is the folder name, everything below is the reason,
with the session's uuid/cwd/turn-count/bytes shown as comments for context while naming.
Then the pipe.

**`ccresume [-i] [-r] <name>`** — the inverse of `ccstash`. Copies the transcript back to
the `project_dir` recorded in `meta.yaml`, then `claude --resume <uuid>` in a new tmux
window. Never overwrites an existing transcript: the original is the live one and may
have turns the archive lacks.

**`ccfind [-p] [--list] [query]`** — fzf over the archive. Each line is
`name  date  why | opening prompt`, so typing matches your own words and how the
conversation started, not just the folder name.

## Decisions

**The editor runs before any copying.** Aborting it (`:cq`, or a blank name) leaves
nothing on disk to clean up, so there is no rollback path to get wrong.

**The popup is created by the tmux binding, not by `ccsave`.** A `display-popup -E`
issued from `run-shell` returns *immediately* rather than waiting for the command to
exit, so a self-popping `ccsave` would copy before you finished typing the name. Same
shape as the existing `prefix e` binding. `prefix C-a` needs no `run-shell` hop at all
because it expands no format.

**No index file.** `ccfind` computes its listing from `*/meta.yaml` on every invocation.
Nothing can go stale, and renaming or deleting a folder by hand needs no follow-up — a
deliberate contrast with `PLANS_TOC.md`, whose entry for this feature's own predecessor
outlived the plan it pointed at.

**Free text lives outside `meta.yaml`.** `why.md` and `first-prompt.txt` are separate
files, so nothing ever has to escape arbitrary prose into YAML; every value in
`meta.yaml` is a uuid, an absolute path, or a date.

**Names are never generated.** `ccsave` prefills nothing but mechanical facts. A prior
in-house Haiku namer (whose `ai-title` records are still in the corpus, and which is not
a Claude Code feature) produced stale titles, because a name minted early stops
describing a conversation that keeps going.

**`project_dir` is recorded, not recomputed** — the slug mangling above.

**Copy, don't own.** Rejecting the symlink design costs the in-app `/resume` picker
(archived-then-pruned sessions won't appear there) and makes the copy stale if the
conversation continues after saving — re-run `prefix A` to refresh. What it buys: no
hardlink-then-`cp`-then-`mv -T`-then-`tail -n +N` swap dance, no `relink` repair command,
and no dependency on Claude following a symlink during session discovery, which was the
old design's single unverified load-bearing assumption. `ccrg` was dropped with it: its
JSONL-rendering existed only to make transcript *bodies* greppable, and `why.md` is
small, hand-written, and greppable with plain `rg`.

**Live conversations are archivable.** Verified that Claude appends in place: across two
samples of a running session's transcript one tool call apart, the inode was unchanged
(`60466764`) while size grew 220198 → 235243 bytes. It reopens by path and appends, so a
`cp` of a live transcript is a valid prefix. `ccstash` drops a final unterminated line if
it copied mid-append (one turn lost; re-saving picks it up).

## Follow-up after first real use

The first save from the binding worked; the second printed only tmux's
`'tmux display-popup ...' returned 1`, which is useless, and the saved entry had
`why.md: (no reason recorded)`. Three separate faults:

**tmux's failure notice overwrote ours.** `ccsave`'s `die` writes to the status line, and
so does `run-shell` when its command exits nonzero — last writer wins, which is tmux.
Now `die` holds the popup open (`read -rsn1`, guarded by `[ -t 0 ]`) so the message is
read before the popup closes, and the binding ends with `; true` so tmux stops reporting
an exit status that `ccsave` has already explained.

**Declining to save was reported as a failure.** `:cq` and a blank name are deliberate
choices, so they now exit 0 with a status-line note, via a separate `abort` helper.

**The template made the reason unreachable.** Line 1 (the name) sat above a wall of
comments, so the natural move was to describe the whole conversation *in the name* —
which is what happened: a 54-character folder name and no reason. The block is now
delimited and says explicitly what goes above it and what goes below.

That exposed a fourth issue: adding the reason afterwards meant retyping the exact long
name, or getting a second folder. So:

- Re-saving the **same session under the same name** is a refresh, not a clash: it
  re-copies the transcript (picking up turns since) and keeps the existing `why.md` if
  you supply no new prose. `-f` is now only for taking a name held by a *different*
  conversation — and a `-f` swap deliberately does **not** inherit the old note.
- `ccsave` prefills line 1 with the existing name, and the body with the existing
  reason, when the conversation is already kept. Re-saving is then an edit.
- Saving one conversation under a second name still works, but prints
  `note: also kept as <name>`.

## The SIGPIPE bug

Reported next: a pane whose conversation had subagents failed with `no transcript for
<uuid>`, while `ccpaths <uuid>` printed the transcript perfectly well from a shell. The
cause was in `ccsave`:

```bash
transcript=$("$HERE/ccpaths" "$uuid" | head -1) || die "no transcript for $uuid"
```

A session **with** a sidecar makes `ccpaths` print a second line. `head -1` closes the
pipe, `ccpaths` takes SIGPIPE on its second `printf`, and `pipefail` reports the pipeline
as failed — so the guard fired on a session that was fine, with a message asserting the
opposite. Every session used while building happened to have no sidecar, which is why six
green `ccsave` runs missed it: the bug is invisible in exactly the case that `ccpaths`
prints one line.

Fixed by capturing the whole output and slicing (`paths=$(ccpaths …)`,
`transcript=${paths%%$'\n'*}`). The same shape was then audited out of the rest:

- `ccfind`'s `list()` piped `cat | tr | tr | head -c 600`, which would abort the entire
  listing for any entry whose `why.md` plus opening prompt exceeded 600 bytes. Now
  `blob=${blob:0:600}`.
- `ccresume`'s `meta_get`, `ccfind`'s `saved`, and `ccstash`'s `prev` all read a single
  key through `sed … | head -1`. They are safe only because `meta.yaml` never repeats a
  key; now `sed` quits at the first match (`;/^key: /q`) and there is no pipe to break.
- `ccstash`'s `jq … | head -c 400` stays, already guarded with `|| true`.

The lesson worth keeping: under `set -o pipefail`, `| head` is a failure injector, not a
truncation. Truncate with parameter expansion, or make the producer stop on its own.

## One conversation, more than one entry

Reported next: a conversation that had been saved, talked with further, and had "become
its own conversation" appeared to be rejected as a duplicate with no new entry created.

The mechanism was never the problem — saving the same session under a second name works
and always did. The *interface* was: `ccsave` prefilled line 1 with the existing name and
the header read `already kept; edit and save to update it`, so leaving line 1 alone (the
path of least resistance, since it was already filled in) silently refreshed the old entry
instead of filing a new one, and the only hint otherwise was `ccstash`'s
`note: also kept as …` on stderr — which a closing popup throws away.

The rule stays (same session + same name = update), but the choice is now stated:

- The header lists **every** entry already holding this session, newest first, and spells
  out both branches: leave line 1 → update that entry; change line 1 → file it again
  under an additional name, both resuming the same conversation.
- The prefilled name is the most recently *saved* entry (`ls -td`), not whichever sorted
  first alphabetically.
- The status line distinguishes `updated <name>` from
  `kept as <name> (also kept as <older>)`. After the popup closes it is the only thing
  left, and `kept as X` for what was really an in-place update is what made a second
  entry look impossible.
- `ccfind`'s preview cross-references entries sharing a session, so an older, shorter
  entry points at the longer one.

What two entries mean, precisely: one conversation, two names and two reasons. Transcripts
are cumulative, so the second entry's copy is a superset of the first's, and both
`ccresume` to the same session id — they are two descriptions of one thread, not two
threads.

## The jq regex blowup (why saving appeared to do nothing)

Reported next as "still didn't work" on the same conversation. It was not the duplicate
logic — it was a **hang**, and reproducing it against a copy of the real archive took two
minutes to time out.

`ccstash` extracts the opening prompt with jq, and the filter ran
`gsub("\\s+"; " ")` plus three `test(...)` calls over *whole* message contents. That
transcript contains a **720,766-byte line** (a large paste or tool result), and jq's
regex engine on a string that size takes minutes. `jq -sr 'length'` on the same file is
47 ms, which is why an earlier timing check exonerated jq: the cost is entirely in the
regexes, not the parse.

From the outside this looked like nothing happening: the popup stays open while `ccsave`
waits, and killing it fires `ccstash`'s cleanup trap, which removes the staging directory
— leaving `~/conversations` with a fresh mtime, no new entry, and no debris. That
signature is what identified the failure as mid-copy rather than a rejected save.

Fixed by slicing every string to 400 characters **before** any regex touches it
(`.[0:400] | gsub(…)`), which is sound because the slice keeps the prefix the tag tests
need, and by dropping `-s`: slurping the file is pointless when only the first hit
matters. Same transcript now: **0.15 s**. A `timeout 15` wrapper (when `timeout` exists)
caps any future pathological case at 15 seconds instead of forever.

The filter also now skips `This session is being continued from a previous conversation`,
the compaction-continuation preamble, so a compacted session yields the first real
post-compaction prompt instead of a summary blob.

**Logging.** Three consecutive failures were invisible for the same structural reason: a
popup takes its output to the grave and the tmux status line holds one message briefly.
Every `ccsave` run now appends to `~/.cache/ccsave.log` (`$CCSAVE_LOG`) — the session,
pane, chosen name, `ccstash`'s stderr, and the outcome. `tail ~/.cache/ccsave.log` is now
the first diagnostic step, not a repro attempt.

## Resuming the snapshot, not the live thread

The point of keeping a conversation is being able to *resume the saved state inside
Claude*. The first cut failed at exactly that, and the failure was invisible because the
stored bytes were provably frozen: `bgrun-the-setsid-command-claude-made` held 90 user
messages while its live original had grown to 99, and reopening the entry showed 99.

Cause: `ccresume` refused (correctly) to overwrite a live transcript with an older copy,
then ran `claude --resume <uuid>`. Claude opens a conversation by session id and looks for
its transcript at exactly one path, `~/.claude/projects/<slug>/<uuid>.jsonl` — there is no
"open this file" flag. While the original exists, that path is the live copy, so resuming
by the archived entry's uuid could only ever show the current thread.

The fix treats identity as the thing to change, not the bytes. `ccresume <name>` now:

1. generates a fresh uuid,
2. copies the snapshot to `<project_dir>/<new-uuid>.jsonl`, rewriting `"sessionId"` to the
   new value — the only field carrying it (`session_id`, which also appears, holds an
   unrelated value and is left alone),
3. records the derivation in the entry's `derived.log`,
4. resumes the new id.

The frozen state opens as a genuine, continuable Claude session, and the conversation it
came from is not touched at all. `-l` resumes the live thread instead; if Claude has
already pruned the original, no new id is needed and the snapshot reclaims its own uuid.

Pressing enter twice reuses an already-installed derived session while it is still
byte-identical to the snapshot, so repeated presses do not litter a copy per keypress.
Once you have talked in it, the next resume starts a fresh one from the frozen point,
which is the right behaviour: that thread has diverged.

**Verified end to end**, since this was the design's last unproven assumption:
`claude -p --resume <new-uuid> 'Reply with exactly: RESUME_OK'` answered `RESUME_OK` and
appended to the derived session (31,466 → 47,196 bytes) while the original's mtime stayed
at Aug 13. Claude accepts a transcript it did not create, under a re-identified filename.

`ccview` renders a snapshot as readable text without resuming anything — useful for
reflecting on a conversation rather than continuing it, and the only way to read a frozen
state with no session involved at all.

`ccfind` keys: **enter** resume the snapshot, **ctrl-r** resume live, **ctrl-v** read,
**ctrl-o** edit the folder. Implemented with `--expect` rather than a `become` binding.

Refresh semantics were left as they were, at the user's call: re-saving under the same
name re-copies the transcript, so an entry can be advanced deliberately.

## Updating a snapshot

Pressing `prefix A` on a conversation you *think* you have kept is safe and
self-explanatory: the template lists every entry already holding that session, newest
first, with line 1 prefilled with the most recent name. You do not have to remember
whether or under what name you saved it.

- **Leave line 1 alone** → the entry is refreshed: the transcript is re-copied, so the
  frozen point moves forward to now, and `why.md` is kept if you type no new prose. Status
  line reads `updated <name>`.
- **Change line 1** → a second entry, a snapshot at the current point, with the older one
  left exactly as it was. Status line reads `kept as <new> (also kept as <old>)`.

A refresh therefore *discards* the older frozen point; keeping both means using a new name.
`saved:` is bumped to the refresh date, and the original filing date is not retained.

Interaction with snapshot-resume: after a refresh, a previously derived session no longer
matches the snapshot byte-for-byte, so the next enter in the picker mints a fresh derived
session from the *new* point. Any thread you already opened from the old point is
untouched and still resumable through Claude's own `/resume`.

**Bug found while documenting this.** `ccstash` builds a staging folder and `rm -rf`s the
old one, so a refresh destroyed everything in the entry that `ccstash` does not itself
write — `ccresume`'s `derived.log`, and any notes added by hand. A refresh now carries
over every file it does not own (anything outside `meta.yaml`, `why.md`,
`first-prompt.txt`, `<uuid>.jsonl`, `<uuid>/`, `file-history/`). A `-f` replace by a
*different* conversation still inherits nothing, deliberately.

## Files touched

- `+ bin/ccpaths` — uuid → the paths that exist
- `+ bin/ccstash` — stdin paths → `$CC_ARCHIVE/<name>/`; owns the root
- `+ bin/ccsave` — pane → uuid → popup editor → the pipe
- `+ bin/ccresume` — restore to `project_dir`, then `claude --resume`
- `+ bin/ccfind` — fzf picker; `--list` for piping without a terminal
- `~ .tmux.conf` — `bind-key A`, `bind-key C-a`; both were unbound. `prefix A` ends in `; true`
- `~ CLAUDE.md` — the tmux-conventions paragraph

`run.sh`'s `bin/*` loop symlinks all five onto PATH; no installer change was needed.

## Verification

- `ccpaths` on a session with a sidecar, without one, with `-a`, on a malformed uuid, and
  on an unknown uuid — correct output and exit status in all five.
- `ccstash` end-to-end on three real sessions; `meta.yaml`, `why.md`, `first-prompt.txt`
  and the sidecar all land. `first-prompt.txt` initially captured `/effort` slash-command
  expansion; the jq filter now skips tag-prefixed and `Caveat:` lines and yields the
  first thing the human actually typed.
- `ccsave` against this very pane with a stub `$EDITOR`: happy path, `:cq` abort, blank
  name, name collision, and `-f` replace — five for five.
- `ccresume -r` with the original present (declines, correctly), into an empty project dir
  (restores transcript + sidecar), run twice (idempotent), and on an unknown name.
- `ccfind --preview` and `--list`; search verified via `fzf --filter` to match on the
  name, on `why.md`, and on `first-prompt.txt`. A first cut used
  `--delimiter`/`--with-nth` to hide the search blob — that was wrong: `--with-nth`
  changes what fzf *matches*, not merely what it displays, so the hidden field was
  neither visible nor searchable.
- On the actual failing pane (`%38`, session with a sidecar) after the SIGPIPE fix: saved
  clean, sidecar copied, `ccfind --list` survives a 1201-byte `why.md`, `ccresume -r`
  correctly declines to overwrite the live original.
- After the follow-up: same-session refresh keeps the reason; `-f` swap to a different
  session drops it (caught by regression — the first cut wrongly inherited it); fresh save
  leaves line 1 blank; re-save prefills name + reason; `:cq` and blank name both exit 0.
- `tmux source-file .tmux.conf` clean; both keys present in `list-keys`; the `prefix A`
  binding's quoting verified by having `run-shell` print its expansion —
  `... "/home/jke/dotfiles/bin/ccsave \"%22\""`.

## Open

`claude --resume <uuid>` on a transcript that `ccresume` copied back has **not** been
exercised. Claude finds sessions by the uuid filename in the project dir, so restoring to
the recorded `project_dir` under the original basename should be indistinguishable from
the file never having moved — but "should be" is not "was". Confirm it once with a
conversation you don't mind resuming; if it fails, the fallback is to keep the original in
place (drop the copy) and revisit the symlink model.
