# yazi: track config in dotfiles, write into the shared zoxide database

Verified a claim (from another agent) that yazi's built-in zoxide plugin can write into
the *same* zoxide database the shell's `z`/`zi` read from, via an `update_db` setup
option — confirmed against yazi's actual plugin source
(`yazi-plugin/preset/plugins/zoxide.lua`: `setup()` subscribes to the `"cd"` event and
runs `zoxide add <cwd>` when `opts.update_db` is set) and its official docs. Since the
plugin just shells out to the `zoxide` binary already on `$PATH`, enabling it means
directories browsed in yazi become rankable via `z` in the normal shell too.

`~/.config/yazi/` (`yazi.toml`, `keymap.toml`) existed on disk but wasn't tracked by
dotfiles at all — not in `run.sh`'s symlink list, unlike nvim. Brought it under
management to land the `update_db` option.

## Changes

- `+ yazi/yazi.toml`, `+ yazi/keymap.toml` — moved verbatim from `~/.config/yazi/`
- `+ yazi/init.lua` — `require("zoxide"):setup { update_db = true }`
- `~ run.sh` — symlinks `~/.config/yazi` → `dotfiles/yazi`, guarded:
  ```bash
  [ -d "$HOME/.config/yazi" ] && [ ! -L "$HOME/.config/yazi" ] && rm -rf "$HOME/.config/yazi"
  ln -sf "$DOTFILES/yazi" "$HOME/.config/yazi"
  ```
  Plain `ln -sf` isn't idempotent here: it only replaces an existing *file or symlink* at
  the target path. Since `~/.config/yazi` was a real directory, `ln -sf` alone would have
  nested the link inside it (`~/.config/yazi/yazi -> dotfiles/yazi`) instead of replacing
  it. The guard removes the real directory only the first time; every later run is a
  no-op. nvim's line doesn't need the same guard — `~/.config/nvim` was already converted
  to a symlink by an earlier `run.sh` run, so it's not being freshly converted now.

## Verification

Scripted end-to-end proof rather than trusting the docs: launched yazi via a detached
tmux session (`tmux new-session -d -s yazitest "yazi /home/jeffk/dotfiles/yazi"`) into a
directory not yet in zoxide's history, sent `q` to quit, then confirmed
`zoxide query /home/jeffk/dotfiles/yazi` resolved afterward — proving the write-through
actually lands in the shared database, not just that the plugin loads without error.
Test entry removed with `zoxide remove` afterward.
