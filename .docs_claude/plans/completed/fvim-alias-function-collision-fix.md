# fvim alias/function collision fix

## Context

Found incidentally while testing the fzf Ctrl-T navigation work (see
[fzf-ctrl-t-directory-navigation.md](fzf-ctrl-t-directory-navigation.md)): after picking
up the new config with `source ~/.bashrc` in an already-running shell, bash printed
`syntax error near unexpected token '('` / `` `fvim() {' `` and continued (non-fatal, but
`fvim` was broken for the rest of the session).

Root cause: `fvim` was defined twice — an alias in `machines/tesu.sh` and a function in
`.functions.sh`, both pre-existing and unrelated to this session's other changes. Bash
resolves aliases before functions during parsing, so on a *fresh* shell the alias
silently won — the fancier function (which additionally takes an optional `fd` pattern
to pre-filter before `fzf`) was dead code the whole time. Worse, re-sourcing `.bashrc` in
a shell that already has the alias defined (from its own earlier startup) makes bash trip
trying to parse `fvim() {` as a function definition with the same name as an active
alias — hence the syntax error. Reproduced deterministically: `source ~/.bashrc` twice in
one session, every time.

## Approach

Removed the alias in `machines/tesu.sh`, keeping `.functions.sh`'s `fvim()` as the sole
definition (user's choice — the function is the more capable of the two).

## Files

- `~/dotfiles/machines/tesu.sh` — deleted `alias fvim="nvim \$(fzf)"`

## Verification

`bash -i -c 'source ~/.bashrc; source ~/.bashrc'` — no syntax error (previously
reproduced on every run before the fix), and `type fvim` resolves to the `.functions.sh`
function version, not an alias.
