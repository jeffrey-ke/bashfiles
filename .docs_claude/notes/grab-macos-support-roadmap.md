# `grab` macOS support — roadmap

Cross-platform review (fable model, 2026-07-13) found `grab` won't work on
macOS (`jeffpro`) as shipped. Decomposed into 4 independent sub-projects,
each to be brainstormed/planned/implemented separately. This note tracks
scope and findings; delete once all 4 are done and folded into the plans
index.

**Correction (user, 2026-07-13):** the review guessed `jeffpro`'s daily
shell is zsh, based on `alias fresh="source ~/.zshrc"` in
`machines/jeffpro-3.sh` and `machines/jeffpro/obsidian_zsh` being a zsh
script. **This was wrong — the user confirmed their Mac's interactive
shell is bash.** Specifically **stock `/bin/bash` 3.2** (not a
Homebrew-installed 4.x/5.x) — macOS ships 3.2 forever due to the GPLv3
license switch. This changes sub-project 4 below: it's a bash-3.2
compatibility problem, not a zsh-widget problem.

## 1. Portable reverse-lines (`tac` fix) — CODE DONE, macOS verification OPEN

Shipped: `~/dotfiles/bin/grab` now uses a portable `rev_lines()` (POSIX
awk) instead of GNU-only `tac`, in all three tokenizers. Plan/spec:
[grab-macos-portable-reverse-lines.md](../plans/active/grab-macos-portable-reverse-lines.md)
(deliberately left in `plans/active/`, not moved to `completed/`, until
the open item below is closed). Task-reviewed (one round: found and
accepted a documented edge-case divergence from `tac` on non-newline-
terminated input, which can't fire in `grab`'s real pipeline) and
whole-branch reviewed (Ready to merge: Yes). Verified portable-by-
construction (plain POSIX awk, no GNU extensions) and cross-checked
against `mawk` (a non-gawk implementation) as a portability proxy.

**Still open: no Mac available in this session to actually run it on
macOS.** Move this plan to `completed/` and update `PLANS_TOC.md` only
once someone runs `grab` on `jeffpro` (or another Mac) and confirms it
works there.

## 2. Portable clipboard (`xclip` fix) — SKIPPED, not actually broken

Original review assumption: `bin/grab:74`'s `ctrl-y` uses `xclip
-selection clipboard`, which is X11-only and "doesn't exist on macOS."
**This assumption was wrong for the user's actual Mac** — user confirmed
(2026-07-13) `xclip` is genuinely installed and working there (used by
`.tmux.conf:81-82`'s already-functional `y`/`Enter` copy-mode bindings,
same binary). `grab`'s `ctrl-y` uses the identical `xclip -selection
clipboard` command (no `-in` flag, but that's `xclip`'s own default), so
it already works unmodified on this Mac too.

A candidate portable fix was investigated and verified mechanically
before this was found unnecessary: `.tmux.conf:73`'s `set -s
set-clipboard on` (OSC 52) + `tmux load-buffer -w -` (confirmed via
`tmux show-buffer` to read stdin and populate a buffer correctly, and
per `man tmux`, `-w` sends it to the system clipboard via the xterm OSC
52 escape sequence). User explicitly chose not to switch to this —
`xclip` isn't broken for them, and swapping would be work for a problem
they don't have. Revisit only if a *different* Mac (without `xclip`
installed) needs `grab`, or if `xclip`'s XQuartz/Homebrew dependency
ever becomes inconvenient to maintain.

## 3. Cross-platform install/bootstrap — DONE, verified on macOS 2026-08-11

Shipped: plan/spec at
[grab-macos-install-bootstrap.md](../plans/completed/grab-macos-install-bootstrap.md)
(moved to `completed/` once the open item below was closed). Two
tasks, both task-reviewed and whole-branch reviewed (Ready to merge:
Yes, one Minor cosmetic fix applied post-review):

- `run.sh` now symlinks `bin/`'s user commands (`art`, `commentstrip`,
  `fgr`, `grab`, `pydef`, `run` — extensionless executables only, verified
  against a fixture mirroring the real directory) into `~/.local/bin`,
  and fixes the GNU-only `sed -i '/MACHINE_CONFIG/d'` line (BSD sed
  requires an explicit suffix argument) to the portable `sed -i.bak
  '...' file && rm file.bak` form — verified on GNU sed, not on real BSD
  sed (no Mac available).
- `install-tools.sh`'s `install_fzf`/`install_yazi` now branch on
  `uname -s = Darwin` and shell out to `brew install <tool>` instead of
  the (broken-on-macOS) GitHub-release-download path — chosen over
  replicating the download approach with Darwin asset URLs after finding
  yazi's Apple-Silicon asset name (`aarch64`) doesn't match macOS's own
  `uname -m` output (`arm64`), an extra footgun Homebrew's own platform
  detection avoids. Existing Linux paths and `install_zoxide` are
  provably byte-for-byte unchanged. The install loop's success check now
  requires `"$tool" --version` to actually succeed, not just `command -v`
  — directly closes the Intel-Mac false-success bug (downloads a Linux
  binary, reports "✓ installed", binary can't execute) generally, not
  just for this one case.

Every mechanism was proven with real mock/fixture tests on this Linux
machine during brainstorming and again during implementation (fake
`uname`/`brew`, a broken-binary fixture, a `bin/`-mirroring fixture) —
not just asserted.

**Closed 2026-08-11 on `jke-laptop`** (a second Mac, not `jeffpro`). All
three release conditions confirmed: the six `bin/` symlinks land, BSD
`sed -i.bak` runs clean under `set -e`, and `brew install` succeeds for
fzf/yazi/nvim. Running it for real also turned up what a Linux-only
session couldn't:

- The Darwin branch was missing from `install_fd`/`install_rg`/
  `install_git_lfs`, so six of nine tools failed on a fresh Mac. `git-lfs`
  was the one with teeth — `.gitconfig` sets `filter.lfs.required`, so LFS
  repos hard-fail rather than degrade. Now brew-branched like the rest.
- `rust_target`'s `return 1` was being swallowed by the `$(...)` it's
  called in, degrading the asset pattern to a bare `\.tar\.gz` that
  matches whichever archive a release lists first — the *correct* Apple
  Silicon build for both fd and ripgrep today, purely by luck of ordering.
  Now checked explicitly.
- Homebrew being installed isn't enough: `/opt/homebrew/bin` isn't on the
  default macOS PATH, and Homebrew only prints the `shellenv` line for you
  to add. `.bash_tools` now evals it (guarded), which is what makes the
  brew-delegated tools visible to both the installer's own `command -v
  brew` guard and the integration blocks below it.
- Nothing `run.sh` appends to `.bashrc` loaded at all, because macOS ships
  no `.bash_profile`/`.bash_login`/`.profile` and Ghostty/Terminal start
  the shell via `login`. `run.sh` now patches whichever login file exists,
  creating a one-line `.bash_profile` only when none do (creating one on
  Ubuntu would shadow its `.profile`).

## 4. CTRL-G on bash 3.2 (corrected scope — not zsh)

`.bash_tools`'s `_grab_insert` relies on `READLINE_LINE`/`READLINE_POINT`,
introduced in **bash 4.0**. macOS's stock `/bin/bash` is 3.2.57 (frozen,
GPLv3). Under 3.2, `bind -x` still exists but `READLINE_LINE`/
`READLINE_POINT` don't — `_grab_insert` would run (CTRL-G "fires") but the
assignments have no effect on the actual edit line, so nothing gets
inserted.

**Real, reusable precedent found in this exact environment:** `fzf --bash`
(the same integration `.bash_tools:10` already sources) ships its own
bash-3.2 fallback, gated on `if ((BASH_VERSINFO[0] < 4))`. Instead of
`bind -x` + `READLINE_LINE`, it binds a **macro string** of literal
readline key sequences that kill the current line, type a backtick
command-substitution (`` `__fzf_select__` ``), and force a redraw —
e.g. for CTRL-T:
```
bind -m emacs-standard '"\C-t": " \C-b\C-k \C-u`__fzf_select__`\e\C-e\C-\e(\C-a\C-y\C-h\C-e\e \C-y\ey\C-x\C-x\C-f\C-y\ey\C-_"'
```
paired with a separately-bound redraw trigger:
```
bind -m emacs-standard '"\C-\e(": redraw-current-line'
```
This is battle-tested (fzf's actual shipped code, used by macOS's default
bash for years) and directly adaptable for `_grab_insert`'s CTRL-G binding
— study `fzf --bash`'s full bash<4 branch (`fzf --bash | sed -n
'131,150p'` on any machine with fzf installed) as the reference
implementation before designing this sub-project.

## Order

User picked **#1 first**. Order for the rest not yet decided — revisit
after #1 ships.
