# .aliases sourcing at every navigation entry point

## Context

The per-directory `.aliases` mechanism — `cd` sources a `.aliases` file for every
component of the destination path, so a project directory can define shell functions
scoped to itself — has moved around a lot: added to `.functions.sh` in `527f08e` over
`builtin cd`, made cross-platform in `599abe6`, folded into `machines/tesu.sh` next to
zoxide in `75fc442`, and finally deduped into `.bash_tools` in `20023f0`. It ended up
there because it has to wrap zoxide's `cd`, which means it must be defined *after*
`eval "$(zoxide init --cmd cd bash)"`; `.bashrc` sources `.functions.sh` before
`.bash_tools`, so the intuitive home for a shell function would be silently clobbered.

Writing the first real consumer (a project-local `.aliases` in the Nuro monorepo, giving
`learning/unusual_scenes/relevance_filter` an `rf`/`rf_dry`/`rf_probe`/`rf_test` wrapper
around a long `bazel run` invocation) surfaced the fact that only `cd` ever got wrapped.
Every other way this config has of landing in a new directory bypassed the mechanism:

- **`cdi`** — zoxide's interactive fzf picker. `zoxide init` defines both `cd` and `cdi`,
  and `.bash_tools` only ever redefined the former, so `cdi` was still stock
  `cdi () { __zoxide_zi "$@"; }`.
- **`y`** — the yazi cwd-on-exit wrapper (`5958b30`), which uses `builtin cd -- "$cwd"`
  verbatim from the upstream yazi snippet. The `builtin` there is incidental to yazi's
  docs, not a deliberate opt-out.

fzf's Ctrl-T helpers also call `cd` (`_fzf_ctrl_t_up`/`_down`/`_origin`), but those run
inside the `become` chain in a subprocess and only insert text into the command line —
they never change the interactive shell's cwd, so they are correctly not a consumer.

## Approach

Hoisted the path-walking loop out of `cd` into `_source_path_aliases`, then called it
from all three entry points. Two details worth recording:

- The helper sits at **top level**, not inside the `if command -v zoxide` block. `y` needs
  it on a machine that has yazi but not zoxide, which is a real state — `.bash_tools` is
  explicitly written so each tool's block is a no-op when that tool is absent.
- The `_CD_SOURCING` re-entrancy guard (which stops an `.aliases` that itself calls `cd`
  from walking further) moved from `cd`'s scope into the helper's. It still works, because
  bash's `local` is dynamically scoped: the `source` happens inside
  `_source_path_aliases`, so a sourced file's own `cd` → `_source_path_aliases` sees the
  caller's `_CD_SOURCING=1` and returns early. This is the one thing in the refactor that
  could have quietly broken, so it has a dedicated test below.

Deliberately left alone: `pushd`/`popd`, and the `builtin cd` inside the new Nuro
`.aliases`. That one is a subshell that exists only to give `bazel` a workspace cwd —
routing it through the wrapper made every run log start with 47 lines of the `.aliases`
file echoed back by the wrapper's own `echo`/`cat`, and bumped the directory's zoxide
frecency score once per run.

## Files

- `~/dotfiles/.bash_tools` — extracted `_source_path_aliases` to top level; `cd` and the
  new `cdi` wrapper both call it; `y` gained `&& _source_path_aliases`
- `Nuro/learning/unusual_scenes/relevance_filter/.aliases` — the motivating consumer,
  outside this repo. Untracked there: `.aliases` matches no ignore rule in the monorepo
  or in `gitignore_global`, and that file's header documents a deliberate policy of
  keeping dotfiles visible to telescope, so ignoring it globally is a real tradeoff and
  was left as the user's call.

## Verification

All in `bash -i`, since **non-interactive bash never loads `.bashrc`** and therefore has
`cd` as a plain builtin — an earlier pass verified the Nuro `.aliases` under `bash -c` and
missed the wrapper interaction entirely. Any test of this mechanism must be interactive.

- **Regression** — `cd` into a directory with `.aliases` still sources it; and a fuzzy
  `cd relevance_filter` from `~` resolves through the zoxide database and defines `rf`,
  confirming the wrapper covers database jumps and not just literal paths.
- **Re-entrancy guard** — fixture where `a/.aliases` runs `cd` into `b`, and `b/.aliases`
  echoes a marker. `cd a` sources `a/.aliases` and lands in `b` with the marker
  unprinted: the guard survived the move into the helper.
- **`cdi`** — stubbed `__zoxide_zi` to land in the fixture directory (the real one needs
  interactive fzf); `.aliases` sourced.
- `bash -n` clean. `shfmt` is not installed on this machine, so formatting was matched to
  the file's existing tabs by hand rather than reformatted blind.
