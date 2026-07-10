---
name: meta-repo-submodules
description: Maintain a meta git repo (superproject) of submodules — commit changes inside child modules, push them, and bump the recorded pins in the meta repo. Cross-machine aware: safely reconciles when a child has unpushed local commits or unstaged changes on one machine while another machine already pushed child + meta updates. Use when the user says "bump the pins", "commit the submodules", "sync the workspace", or hits a detached-HEAD / "new commits" / gitlink-conflict situation in a superproject.
argument-hint: optionally name the child module(s) to bump, or "reconcile" for the cross-machine merge
allowed-tools: Read, Bash(git:*)
---

# Maintain a Meta Repo of Submodules

A **meta repo** (superproject) tracks each submodule by a single recorded commit SHA — the **pin** (a `gitlink` entry in the tree). The pin is the source of truth; submodules never "follow latest" on their own. Two repos move independently: the **child** (real commits + push) and the **meta** (a pointer bump that records the child's new SHA).

Your job has two halves:
1. **Commit child changes, push them, then bump the pin** in the meta repo.
2. **Reconcile cross-machine divergence** — when machine A already pushed child commits *and* the meta bump, while machine B has its own unpushed child commits or unstaged changes that must not be lost.

## The one invariant that prevents data loss

**A child must be on a real branch (never detached HEAD) before it has commits you care about, and you must NEVER run `git submodule update` while a child has uncommitted or unpushed work.** `git submodule update` checks out the meta's recorded SHA in **detached HEAD**, silently orphaning any local child commits. Cross-machine safety is entirely about ordering operations so this never happens: **children first (commit → rebase → push), meta last.**

## One-time hardening (run once per clone)

```bash
git config push.recurseSubmodules check   # BLOCK a meta push if any pinned child commit isn't on its remote
git config status.submodulesummary 1      # show what moved in `git status`
git config diff.submodule log             # readable submodule diffs (commit list, not raw SHAs)
git config fetch.recurseSubmodules on-demand
# Deliberately DO NOT set `submodule.recurse true` globally here — auto-update on pull is
# exactly what orphans local child work during a reconcile. Recurse explicitly when safe.
```

`push.recurseSubmodules check` is the seatbelt: it makes a meta push fail loudly rather than recording a pin nobody else can fetch.

## Step 0 — Always diagnose before touching anything

```bash
git submodule status --recursive          # leading char per child (see legend)
git fetch --recurse-submodules            # get remote state WITHOUT moving any working tree
# unpushed child commits (data that would be lost by a careless update):
git submodule foreach --quiet 'git log --oneline @{u}.. 2>/dev/null && echo "  ^unpushed in $name" || true'
# dirty child worktrees:
git submodule foreach --quiet 'git -c color.ui=always status --short'
# META-BRANCH divergence vs its own origin — did another machine push a meta bump you don't have?
git rev-list --left-right --count @{u}...HEAD   # "<behind>  <ahead>" of the meta's upstream
git --no-pager log --oneline HEAD..@{u}         # the incoming meta commits (often a rival pin bump)
```

**Check the meta branch against its origin, not just the children.** `git submodule status` only
compares each child to the *local* pin — it is blind to a meta bump another machine already pushed. The
`@{u}...HEAD` count tells you which path you're on:
| `<behind> <ahead>` | Meaning | Action |
|------|---------|--------|
| `0 0` | meta in sync with origin | Recipe A (single-machine happy path) |
| `0 N` | only you advanced the meta | Recipe A, then `git push` |
| `M 0` | origin advanced; you have no meta commit yet | FF/rebase onto `@{u}` **before** committing your bump |
| `M N` | both advanced the meta (rival pin bump) | **Recipe B** — rebase your bump onto `@{u}`, expect a gitlink conflict |

A `behind > 0` count is the tell that a careless `git push` will be rejected and a naive rebase may hit a
gitlink conflict — resolve it the Recipe B way (`git add <submodule>` to take the locally checked-out
merged SHA), never `git submodule update`.

`git submodule status` leading character — **read this first, every time:**
| Char | Meaning | Action |
|------|---------|--------|
| ` ` (space) | child checked out == pin | in sync, nothing to do |
| `+` | child checked out **≠** pin (child moved ahead) | **bump needed** |
| `-` | not initialized | `git submodule update --init` (safe: no local work) |
| `U` | merge conflict inside child | resolve inside child first |

In `git status`, **"(new commits)"** = child has commits past the pin → bump. **"(modified content)"** = dirty worktree → commit inside child. **"(untracked content)"** = untracked files in child.

## Step 1 — Summarize dirty state and propose commit groupings, then ASK

**Always do this before committing anything.** Survey each dirty child, summarize what changed, propose how to split it into coherent commits, and ask the user to confirm or redirect. Do not auto-commit everything in one blob.

Gather the per-child picture:

```bash
# names of dirty / moved children
git submodule foreach --quiet 'echo "=== $name ==="; git -c color.ui=always status --short; \
  git --no-pager diff --stat; git --no-pager diff --cached --stat'
# already-committed-but-unpushed child commits (these need push, not re-commit):
git submodule foreach --quiet 'git --no-pager log --oneline @{u}.. 2>/dev/null'
```

Then present a summary per child and **propose groupings**, e.g.:

```
segmentation   — already has 2 unpushed commits → push only (no new changes to commit)
vision_core    — 6 files dirty. Suggest 2 commits:
                 (a) src/transforms.py, src/geometry.py   — "Add SE3 batch transform helpers"
                 (b) tests/test_transforms.py             — "Test SE3 batch helpers"
reference_matching — 1 file + untracked notebook.
                 (a) proposers/topk.py                    — "Tighten top-k proposer threshold"
                 (?) scratch.ipynb (untracked)            — leave out? add to .gitignore?
```

Group by **coherent intent**, using these signals: same directory/module, code-paired-with-its-test, related symbols touched in the same `diff`, and a shared logical change. Call out the ambiguous bits explicitly — **untracked files** (commit, ignore, or leave?), unrelated changes that snuck into one file (suggest `git add -p` to split), and any child whose only state is unpushed commits (push, don't re-commit).

End the summary with a concrete question — which groups to commit, with what messages, and whether to push + bump now — and wait for the user before running Recipe A. Use `AskUserQuestion` when the choice is a small set of clear options; otherwise ask in prose.

## Recipe A — Commit children + bump pins (single machine, happy path)

For each dirty / moved child:

```bash
cd <child>
git status --short                        # confirm you're on the intended branch, NOT detached HEAD
git switch <branch>                        # if detached: reattach BEFORE committing (see "Detached HEAD recovery")
git add -A
git commit -m "<real message>"
git push                                   # push child to its tracking branch FIRST
cd ..
```

Then record the new SHAs in the meta repo in **one dedicated bump commit** (keep pin bumps out of unrelated feature commits — easier review and rollback):

```bash
git add <child1> <child2> ...             # stages the new gitlink SHAs
git commit -m "Bump pins: <children> — <why>"
git push                                   # `push.recurseSubmodules check` verifies children are reachable
```

Verify: `git submodule status` shows a leading space for every bumped child, and `git submodule foreach 'git log --oneline @{u}..'` is empty.

## Recipe B — Cross-machine reconcile (the careful path)

**Situation:** Machine A pushed child commits **and** the meta bump. Machine B (here) has unpushed child commits and/or unstaged changes in the same children. Goal: integrate *both* sets without losing either. **Order is the whole game — children fully reconciled before meta.**

```bash
# 1. FETCH everything, MOVE nothing. Never `submodule update` yet.
git fetch --recurse-submodules

# 2. Save machine B's local child work so `update`/rebase can't orphan it.
#    Per child with changes (do it deliberately with real messages):
cd <child> && git switch <branch>          # reattach if detached
git add -A && git commit -m "<machine B work>"
cd ..

# 3. Rebase EACH child's branch onto its updated remote — replays B's commits
#    on top of A's already-pushed commits. Resolve child conflicts here, in the child.
git submodule foreach 'git rebase @{u} || true'   # or per-child: cd <child> && git pull --rebase
#    Each child now sits at a NEW merged SHA containing A's + B's commits.

# 4. Push the reconciled children FIRST (meta must only point at reachable commits).
git submodule foreach 'git push || true'

# 5. Bump meta pins to the merged child SHAs.
git add <children>
git commit -m "Bump pins after cross-machine rebase: <children>"

# 6. Reconcile meta with machine A's meta bump. Disable auto submodule-update
#    for THIS command so a mid-rebase checkout can't reset children to A's old SHA.
git -c submodule.recurse=false pull --rebase
#    Equivalent and clearer: git fetch && git -c submodule.recurse=false rebase origin/<metabranch>

# 7. Push meta. `push.recurseSubmodules check` confirms every pin is reachable.
git push
```

### Resolving the gitlink conflict in step 6 (expected, not an error)

Both machines edited the same submodule pin in the meta tree, so the rebase stops with a conflict on the submodule path. **Do not** `git checkout --ours/--theirs` a gitlink — ours/theirs are confusing and swapped during rebase. Instead, the child working tree is **already** at the correct merged SHA from step 3, so just record it:

```bash
git submodule status <submodule>          # confirm checked-out SHA is the merged one you pushed
git add <submodule>                        # take the locally checked-out (merged) SHA
git rebase --continue
```

**Critical:** do **not** run `git submodule update` anywhere inside step 6 — it would reset the child to A's recorded SHA and silently drop B's commits, undoing the whole reconcile.

## Detached HEAD recovery (child has commits but no branch)

If `git submodule status` shows a child at a bare SHA (no `(heads/...)`) and you have local commits on that detached HEAD:

```bash
cd <child>
git switch -c rescue-$(git rev-parse --short HEAD)   # name a branch on the current commit so it's not orphaned
git switch <intended-branch>
git rebase rescue-...        # or cherry-pick the rescued commits onto the intended branch
git branch -d rescue-...
```

## When Applying This Skill

1. **Diagnose first (Step 0).** Never act before reading `git submodule status` leading chars and checking for unpushed child commits — they're the data at risk.
2. **Summarize and propose groupings (Step 1), then ask.** Survey each dirty child, propose coherent commit groups (by module/test-pairing/related symbols), flag untracked and ambiguous changes, and confirm with the user before committing — don't blob everything into one commit.
3. **Is this single-machine (Recipe A) or cross-machine divergence (Recipe B)?** If remote already advanced a child *and* the meta bump that you don't have locally, it's B.
4. **Confirm every child with commits is on a real branch** before committing. Reattach detached HEADs first.
5. **Order, always: child commit → child push → meta bump → meta push.** Reconcile order: children fully done (commit, rebase, push) before any meta rebase.
6. **Rebase, not merge** — keep child and meta history linear; pin churn stays readable.
7. **Never `git submodule update` while local child work is uncommitted/unpushed**, and never during a meta rebase.
8. **Pin bumps get their own commit** with a "why", not folded into feature work.
9. **Verify at the end:** `git submodule status` all-spaces, and `git submodule foreach 'git log --oneline @{u}..'` empty (nothing unpushed). Only then is the meta push safe.
