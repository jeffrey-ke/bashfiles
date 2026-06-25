# Fix: regex hostname matching bypassed by path-registry files

**Date:** 2026-06-25
**Files touched:** `source-machine.sh`, untracked `machines/*.sh` committed

## Symptom

"Special regex hostname matching stopped working." On `r###` hosts the shared
config from `machines/r[0-9]+.sh` (zoxide init, the `fresh` alias, `export proj`)
silently stopped loading.

## Root cause

The regex matching itself was never broken — `[[ r191 =~ ^r[0-9]+$ ]]` matches.
It was being **bypassed**. `source-machine.sh` treated exact-vs-regex as
either/or:

```bash
if [ -f "$_mdir/$_host.sh" ]; then
    source "$_mdir/$_host.sh"   # exact wins, and we STOP here
else
    ...regex loop...            # only runs when no exact file exists
fi
```

The `pr` path-registry helper (`.functions.sh:538`) writes registered paths to
`machines/$(hostname -s).sh` — the **exact** filename. So registering any path on
an `r###` host created `machines/r191.sh` / `r033.sh`, which then short-circuited
the regex branch. The shared `r[0-9]+.sh` config never got sourced.

## Fix

Made exact and regex config **additive** instead of exclusive: source the first
regex match as a shared base, then layer the exact-host file on top so
path-registry overrides still win without shadowing the shared config. The exact
file is skipped inside the regex loop so it is only sourced once (last).

## Verification

On `r191`, after the fix:
- `proj` loads from the regex base `r[0-9]+.sh` (previously dropped)
- `assets` loads from the exact `r191.sh` (override still wins)
- zoxide init / `fresh` alias run again
