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

## 2. Portable clipboard (`xclip` fix)

`bin/grab:74` — `ctrl-y` uses `xclip -selection clipboard 2>/dev/null ||
true`. `xclip` is X11-only, doesn't exist on macOS (that's `pbcopy`).
Because of the `|| true` fallback, this doesn't error — it silently
copies nothing, the worst failure shape (looks like it worked).
`.tmux.conf:81-82` uses the identical `xclip ... || true` pattern with no
macOS guard anywhere — no existing precedent in this repo to reuse.
Candidate fix found during review: `.tmux.conf:73` already sets `set -s
set-clipboard on` (OSC 52) — `tmux load-buffer -w -` would route through
that existing mechanism and work on both OSes with no new dependency,
instead of branching on `command -v pbcopy`.

## 3. Cross-platform install/bootstrap

Three separate issues bundled here since they all block `grab` from ever
landing on a fresh Mac, independent of `grab`'s own code:

- `~/.local/bin/grab` symlink is manual/undocumented (same as `art`/`fgr`/
  `pydef` — `run.sh` and `install-tools.sh` never touch `bin/`). Fix:
  a loop in `run.sh` that symlinks every executable in `bin/`.
- `install-tools.sh:26-33` (`install_fzf`) and `:35-49` (`install_yazi`)
  hardcode `linux_*`/`*-linux-musl*` GitHub release asset patterns.
  Apple Silicon (`uname -m` = `arm64`, not `aarch64`) falls through to an
  honest `return 1`. **Intel Mac (`x86_64` matches) is worse: downloads
  the Linux ELF binary, `command -v fzf` succeeds, script reports "✓
  installed fzf" — but running it is `cannot execute binary file`.**
  Needs `darwin_{amd64,arm64}` cases (fzf ships these; yazi doesn't ship
  a musl-equivalent for macOS since musl is Linux-only — needs a
  different install path, e.g. brew or the yazi macOS release asset).
- `run.sh:26` — `sed -i '/MACHINE_CONFIG/d'` is GNU-only syntax; BSD sed
  (macOS) requires `sed -i ''` (empty string arg for no backup suffix).
  `run.sh` itself would error partway through on a fresh Mac.

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
