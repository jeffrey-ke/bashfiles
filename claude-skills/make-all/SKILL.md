---
name: make-all
description: Run pyright on all Python buffers open in the user's nvim session(s), then analyze the output holistically for real bugs. Use when the user says "make all", ":Make", or asks to run pyright on their open files.
argument-hint: [conda-env-name]
allowed-tools: Read, Bash(id:*), Bash(ls:*), Bash(ls /:*), Bash(nvim:*), Bash(pyright:*)
---

# Make All — Pyright on Open Nvim Buffers

Run pyright against every Python file the user has open in nvim, then analyze the results with the debugging methodology from CLAUDE.md: never stop at the first issue, consider multiple causes, and distinguish real bugs from noise.

## Strict Process

### Step 1: Discover nvim sessions

First, get the user's UID:

```bash
id -u
```

Then, using the resolved UID, list nvim sockets:

```bash
ls /run/user/<uid>/nvim.*.0 2>/dev/null
```

- **One session** → proceed to Step 2.
- **Multiple sessions** → for each socket, query its open buffers:

```bash
nvim --server <socket> --remote-expr 'join(map(filter(getbufinfo({"buflisted":1}), "v:val.name !=# \"\""), "v:val.name"), "\n")'
```

Show the user the buffer list for each session and ask which session they want. Wait for their answer before continuing.

- **Zero sessions** → tell the user no nvim session was found and stop.

### Step 2: Collect Python buffers

Query the chosen session for listed buffers whose names end in `.py`:

```bash
nvim --server <socket> --remote-expr 'join(map(filter(getbufinfo({"buflisted":1}), "v:val.name =~# \"\\.py$\""), "v:val.name"), "\n")'
```

If no Python buffers are open, tell the user and stop.

### Step 3: Run pyright

If the user provided a conda environment name as an argument, activate it before running pyright so that third-party imports resolve correctly:

```bash
conda run -n <env> --no-banner pyright <file1.py> <file2.py> ...
```

If no environment was specified, run pyright directly:

```bash
pyright <file1.py> <file2.py> ...
```

### Step 4: Analyze the output

Present the raw error/warning count, then analyze holistically:

1. **Separate noise from signal.** Import errors (`reportMissingImports`, `reportMissingModuleSource`) for well-known third-party packages (torch, numpy, wandb, etc.) are usually pyright not seeing the conda/venv environment. Note these but move on. However, **import errors for local/project packages** (modules that live in the repo or are clearly project-specific) should be flagged as real warnings — a missing local import likely means a module was renamed, deleted, or not yet created.

2. **Investigate everything else.** For each non-noise diagnostic:
   - Read the file at the reported line (and surrounding context).
   - Consider what the error actually implies — a type mismatch might indicate a refactor left something inconsistent, an attribute error might mean a dataclass or NamedTuple changed shape, an incompatible override might mean the base class API drifted.
   - Do NOT assume the first obvious explanation is the only one. Consider:
     - Could this be an accidental unbound variable?
     - Could this reveal hidden coupling between modules?
     - Could multiple errors share a single root cause (e.g., a function signature change that wasn't propagated)?
     - Could a "noise" error actually point to a real problem (e.g., an import that genuinely doesn't exist)?

3. **Group related errors.** If several diagnostics trace back to the same root cause, explain the chain.

4. **Rank by severity.** Prioritize:
   - Errors that would cause runtime failures
   - Type mismatches that indicate logic bugs
   - API drift / incompatible overrides
   - Cosmetic type annotation issues

## Permitted Tools

Only use these tools during this skill:
- **Bash**: to run `ls` for nvim sockets, `nvim --server ... --remote-expr ...` to query buffers, and `pyright` to run the analyzer
- **Read**: to read file contents at diagnostic locations for analysis

Do not edit files, write files, or run any other commands.
