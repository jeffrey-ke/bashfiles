# Plan: Machine-Specific Long-Path Registry

## Context

The user keeps navigating to a handful of deep paths. zoxide handles *travel* well, but they
want a curated **registry of named paths** that can be **splatted into any position** of a
command — not just command position. Shell **aliases can't do this**: they only expand as the
first word of a simple command. The primitive that expands *anywhere* on the line — and
tab-completes subdirectories (`$proj/<TAB>`) — is an ordinary shell **variable** (`$name`).

So the registry is a set of exported `name -> /long/path` variables. The registry must be
**machine-specific** and must **reuse the existing per-machine machinery** rather than adding a
parallel system.

### Why this design fits the existing machinery (verified)
- `.bashrc` sources `.functions.sh` (~line 161) **before** the per-machine file
  `machines/$(hostname -s).sh` (~lines 169-170: `MACHINE_CONFIG=...; [ -f ] && source`).
- `.functions.sh` is **symlinked** from `~` into the repo → edits are live for new shells.
- `machines/<hostname>.sh` is sourced **directly from the repo path** (not a `~` symlink), is
  **git-tracked**, and already exists for this host (`tesu`).
- Existing model: `aa()` in `.functions.sh:94` (applies to session, then sed-replaces or appends
  a persisted line, then echoes confirmation). We mirror its style.

**Split:** *mechanism* (functions) → shared `.functions.sh`; *data* (the paths) → a marker block
inside `machines/$(hostname -s).sh`. Result: **no new files, no new symlinks, no `run.sh` or
`.bashrc` changes.** Data is per-machine and version-controlled automatically.

### Decisions
- Names: **`pp`** (put), **`pl`** (list), **`prm`** (remove), **`to`** (jump). All verified
  collision-free on `tesu`.
- Scope: **full** — includes `to` + bash tab-completion for `to`/`prm`.
- Missing paths: **reject** — `pp` refuses a path that isn't an existing directory.

## Files to modify
- `/home/jeffk/dotfiles/.functions.sh` — append the registry block (helpers + `pp`/`pl`/`prm`/`to`
  + `complete` lines) at the end of the file. **Only file edited by hand.**
- `/home/jeffk/dotfiles/machines/tesu.sh` — *not* edited by hand; `pp` lazily writes a marker
  block here on first use.

## Implementation

Append to the end of `.functions.sh`:

```bash
# --- path registry: machine-specific long-path -> short $var registry ---
# Mechanism lives here (shared, symlinked). Data lives in a marker block inside
# machines/<hostname>.sh (git-tracked, already sourced by .bashrc) -> per-machine.

_pr_file() { printf '%s\n' "$HOME/dotfiles/machines/$(hostname -s).sh"; }
_pr_begin='# >>> path registry >>>'
_pr_end='# <<< path registry <<<'

# Echo the registered path for $1 (empty if none). Reads only inside the block.
_pr_get() {
	local file; file="$(_pr_file)"; [ -f "$file" ] || return 0
	awk -v b="$_pr_begin" -v e="$_pr_end" -v nm="$1" '
		$0 == b { inblk=1; next }
		$0 == e { inblk=0; next }
		inblk && $0 ~ ("^export " nm "=") {
			line=$0; sub("^export " nm "=", "", line)
			gsub(/^'\''|'\''$/, "", line); print line; exit
		}' "$file"
}

# Echo registered names, one per line (for completion).
_pr_names() {
	local file; file="$(_pr_file)"; [ -f "$file" ] || return 0
	awk -v b="$_pr_begin" -v e="$_pr_end" '
		$0 == b { inblk=1; next }
		$0 == e { inblk=0; next }
		inblk && /^export [a-zA-Z_][a-zA-Z0-9_]*=/ {
			line=$0; sub(/^export /, "", line)
			print substr(line, 1, index(line, "=")-1)
		}' "$file"
}

pp() {
	if [ $# -lt 1 ] || [ $# -gt 2 ]; then
		echo "Usage: pp <name> [path]   (path defaults to current dir)"; return 1
	fi
	local name="$1" raw="${2:-$PWD}"
	if ! [[ "$name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
		echo "Error: '$name' is not a valid variable name."; return 1
	fi
	# Reject non-existent paths (per decision): require an existing directory.
	local path
	if ! path="$(realpath -e -- "$raw" 2>/dev/null)" || [ ! -d "$path" ]; then
		echo "Error: '$raw' is not an existing directory."; return 1
	fi
	if type "$name" >/dev/null 2>&1; then
		echo "Warning: '$name' also names a command/alias/function; \$$name still works as a var."
	fi
	if [ -n "${!name+set}" ] && [ -z "$(_pr_get "$name")" ]; then
		echo "Warning: '$name' shadows an existing environment variable."
	fi
	export "$name=$path"

	local file; file="$(_pr_file)"
	if [ ! -f "$file" ]; then
		mkdir -p -- "$(dirname -- "$file")"; printf '#!/bin/bash\n' > "$file"
	fi
	if ! grep -qF -- "$_pr_begin" "$file"; then            # leading \n: tesu.sh has no trailing newline
		printf '\n%s\n%s\n' "$_pr_begin" "$_pr_end" >> "$file"
	fi
	local esc="${path//\'/\'\\\'\'}" line
	line="export $name='$esc'"
	local tmp; tmp="$(mktemp -- "${file}.XXXXXX")" || return 1
	awk -v b="$_pr_begin" -v e="$_pr_end" -v nm="$name" -v ln="$line" '
		$0 == b { inblk=1; print; next }
		$0 == e { if (inblk && !done) print ln; inblk=0; done=0; print; next }
		inblk && $0 ~ ("^export " nm "=") { print ln; done=1; next }
		{ print }' "$file" > "$tmp" && cat -- "$tmp" > "$file"
	rm -f -- "$tmp"
	echo "Registered \$$name -> $path"
	echo "Use anywhere, e.g.: ls \$$name/   cd \$$name   to $name"
}

pl() {
	local file; file="$(_pr_file)"
	if [ ! -f "$file" ] || ! grep -qF -- "$_pr_begin" "$file"; then
		echo "No paths registered on this machine ($(hostname -s)) yet."
		echo "Register one with: pp <name> [path]"; return 0
	fi
	local pairs
	pairs="$(awk -v b="$_pr_begin" -v e="$_pr_end" '
		$0 == b { inblk=1; next }
		$0 == e { inblk=0; next }
		inblk && /^export [a-zA-Z_][a-zA-Z0-9_]*=/ {
			line=$0; sub(/^export /, "", line); eq=index(line,"=")
			nm=substr(line,1,eq-1); val=substr(line,eq+1)
			gsub(/^'\''|'\''$/, "", val); printf "%s\t%s\n", nm, val
		}' "$file")"
	[ -z "$pairs" ] && { echo "No paths registered on this machine ($(hostname -s)) yet."; return 0; }
	printf '%s\n' "$pairs" | column -t -s $'\t'
}

prm() {
	[ $# -ne 1 ] && { echo "Usage: prm <name>"; return 1; }
	local name="$1" file; file="$(_pr_file)"
	if [ ! -f "$file" ] || [ -z "$(_pr_get "$name")" ]; then
		echo "'$name' is not registered on this machine."; return 1
	fi
	unset "$name"
	local tmp; tmp="$(mktemp -- "${file}.XXXXXX")" || return 1
	awk -v b="$_pr_begin" -v e="$_pr_end" -v nm="$name" '
		$0 == b { inblk=1; print; next }
		$0 == e { inblk=0; print; next }
		inblk && $0 ~ ("^export " nm "=") { next }
		{ print }' "$file" > "$tmp" && cat -- "$tmp" > "$file"
	rm -f -- "$tmp"
	echo "Removed \$$name from the registry."
}

to() {
	[ $# -ne 1 ] && { echo "Usage: to <name>"; return 1; }
	local name="$1"
	[ -z "${!name+set}" ] && { echo "Error: \$$name is not set (try: pl)."; return 1; }
	local target="${!name}"
	[ ! -d "$target" ] && { echo "Error: \$$name -> '$target' is not a directory."; return 1; }
	builtin cd -- "$target"        # bypass the zoxide cd() wrapper for a deterministic jump
}

_pr_complete() {
	local cur="${COMP_WORDS[COMP_CWORD]}"
	COMPREPLY=( $(compgen -W "$(_pr_names)" -- "$cur") )
}
complete -F _pr_complete to
complete -F _pr_complete prm
```

### Why the awk edits are safe
- Markers matched by **exact full-line equality** (`$0 == b`) — a path containing the marker text
  can never be mistaken for a marker.
- Edit/replace lines are **anchored** (`^export name=`) and **gated by `inblk`**, so a same-named
  `export` elsewhere in `machines/<hostname>.sh` (e.g. `export DATA=...`) is never touched.
- `name` is validated as a shell identifier first, so the dynamic awk regex contains no metachars.
- Single insert guarded by `done` → re-running `pp <name>` updates in place; never duplicates
  (idempotent, like `aa`).
- Temp file via `mktemp` then `cat > "$file"` preserves the tracked file's inode/mode.

## Edge cases handled
- Spaces in paths (everything quoted; values single-quoted; `pl`/completion split on `\t`/newline).
- Machine file or marker block absent → created lazily; leading `\n` avoids gluing onto
  `tesu.sh`'s no-trailing-newline last line.
- zoxide `cd()` wrapper: `cd $proj` still works; `to` uses `builtin cd` to be side-effect-free.
- `.functions.sh` is sourced twice by `.bashrc` (161 & 177) — redefining funcs / re-`complete` is harmless.

## Known limitation
Bash-targeted (`[[ =~ ]]`, `${!name}`, `COMP_WORDS`). `tesu` is bash, so this is fine. zsh-primary
machines (e.g. jeffpro) would need minor adaptation and aren't in scope here.

## Verification
1. `source ~/.functions.sh` (or open a new shell / `fresh`).
2. `cd /some/deep/dir && pp proj` → prints `Registered $proj -> /some/deep/dir`; confirm a
   `# >>> path registry >>>` block with `export proj='...'` now exists in `machines/tesu.sh`.
3. Splat test: `echo $proj`, `ls $proj/` (and verify `$proj/<TAB>` completes subdirs).
4. `pp proj /etc` (re-register) → block updated **in place**, no duplicate line.
5. `pp bad /no/such/dir` → rejected with an error, nothing written.
6. `pl` → aligned `name  path` table for this host.
7. `to <TAB>` → completes `proj`; `to proj` → cwd changes to the registered dir.
8. `prm proj` → unset in session and line removed from the block; `pl` no longer lists it.
9. `git -C ~/dotfiles diff machines/tesu.sh` → shows the registry changes, ready to commit.
