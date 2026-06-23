---
name: uv-slurm-jobs
description: Write and debug Slurm/sbatch (or any non-interactive) job scripts that use uv on HPC clusters, including getting Weights & Biases (wandb) working in batch jobs. Use when creating batch scripts that call `uv run`/`uv pip`, when a command works in an interactive shell but fails under the scheduler, or when diagnosing "uv: command not found", disk-quota errors, torch "cuda avail: False", or wandb auth/egress failures inside a job.
argument-hint: [cluster name or what the job should run]
allowed-tools: Read, Write, Edit, Bash(sbatch:*), Bash(squeue:*), Bash(sacct:*), Bash(uv:*), Bash(ssh:*), Bash(rsync:*), Bash(scp:*)
---

# uv in Slurm / Batch Job Scripts

A batch script runs in a **non-login, non-interactive** shell, usually on a **different node**. It reads **neither** `~/.bashrc` **nor** `~/.bash_profile`, so nothing your interactive shell set up (PATH to `uv`, the `module` function, aliases) exists. It inherits only the **exported environment variables** the scheduler hands it. Almost every "works in my shell, breaks in the job" bug is a consequence of this. Reconstruct what you need explicitly.

## Core Recipe — minimal working uv batch job

The single load-bearing line is putting `uv` on `PATH`. A complete, correct job can be this short:

```bash
#!/bin/bash
#SBATCH -p <partition>
#SBATCH -t 0:10:00
#SBATCH -o job_%j.out          # %j = job id; lands in the submit dir
#SBATCH -e job_%j.err

# The batch shell never read ~/.bashrc — put uv on PATH by hand.
# Installer drops it in ~/.local/bin (curl installer) or ~/.cargo/bin (old).
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

uv run myscript.py             # uv finds its own Python + builds the env
```

That's it for "make uv run." Everything below is for running it *well* (quota, GPUs, reproducibility, debuggability).

## Keep big caches off the home quota (persistent, inheritance-free)

uv's wheel cache + downloaded Pythons + venvs are multi-GB (torch alone ~5 GB). Cluster `$HOME` is usually a small quota (e.g. 25 GB) → the first big install dies with a confusing "Permission denied" / "No space" deep in the run. Point uv at large project/scratch storage.

**Best — `~/.config/uv/uv.toml`** (read from disk in *every* context: login or not, interactive or not, sbatch or ssh — no env inheritance required):

```toml
cache-dir = "/large/fs/<user>/.uv-cache"
```

Verify with `uv cache dir`. After this, drop cache handling from the scripts entirely.

**Alternative — env vars** (inherited by jobs via Slurm's default `--export=ALL`; set in the cluster's `~/.bash_profile`):

```bash
export UV_CACHE_DIR="/large/fs/<user>/.uv-cache"
export UV_PYTHON_INSTALL_DIR="/large/fs/<user>/.uv-python"
```

Precedence is **CLI flag > env var > uv.toml** — if you set both, keep them consistent. Prefer `uv.toml`: it has no dependency on `--export` or on which shell launched the job.

## PyTorch on GPU clusters — ALWAYS pin the CUDA build

Cluster GPU drivers lag the newest CUDA. If you let uv grab the default torch wheel it may be too new for the driver, and `torch.cuda.is_available()` silently returns `False` — looking like a code bug while it's a wheel/driver mismatch. **Match the wheel to the driver.**

1. Read the driver's max CUDA from `nvidia-smi` (top-right "CUDA Version", e.g. 12.6).
2. Pick the matching PyTorch index: CUDA 12.6 → `cu126`.
3. Pin it. In a PEP 723 inline script (works with `uv run script.py`):

```python
# /// script
# requires-python = ">=3.10"
# dependencies = ["torch"]
#
# [tool.uv.sources]
# torch = { index = "pytorch-cu126" }
#
# [[tool.uv.index]]
# name = "pytorch-cu126"
# url = "https://download.pytorch.org/whl/cu126"
# explicit = true          # keep PyPI default for torch's OTHER deps
# ///
import torch
assert torch.cuda.is_available(), "torch cannot see the GPU"
```

In a real project use the same `[tool.uv.sources]` + `[[tool.uv.index]]` stanza in `pyproject.toml`. `UV_TORCH_BACKEND=auto` exists but is unreliable for `uv run` and can't bust a cached env — prefer the explicit pin.

## Weights & Biases (wandb) in a batch job

Three things a job doesn't inherit and you must supply. Same disease as `uv` on PATH — credentials and config don't cross into the non-login shell on their own.

1. **wandb must be a dependency.** Add `wandb` to the PEP 723 `dependencies` (or `pyproject.toml`) so `uv run` builds it into the env.

2. **Auth — give the job a credential.** Two ways, both inheritance-free:
   - `wandb login` once on the cluster → writes `~/.netrc`. Because `~/.netrc` is a file on the shared home FS, the job reads it regardless of shell type (same logic as `uv.toml`). This is the simplest path.
   - `export WANDB_API_KEY=...` — survives `--export=NONE` if set in-script; good for fully self-contained jobs.
   With neither, online `wandb.init()` fails on **auth**, not egress — don't confuse the two.

3. **Egress — does the compute node reach `api.wandb.ai`?** Often it does (verified on PSC Bridges-2 2026-06-19: compute nodes reach wandb cloud and sync live). **Test reachability by HTTP status code, never `curl -f`:** `api.wandb.ai` returns `404` on `/` and `405` to a GET on `/graphql` — both *prove* reachability, but `-f` treats any 4xx as failure and reports a false "UNREACHABLE". Correct probe:

   ```bash
   code=$(curl -sS -m 15 -o /dev/null -w '%{http_code}' https://api.wandb.ai/graphql 2>/dev/null || echo 000)
   [ "$code" != "000" ] && echo "reachable (HTTP $code)" || echo "no route (000)"
   ```

   If a cluster genuinely blocks egress (status `000`), use **offline + sync**: run with `WANDB_MODE=offline` (writes `wandb/offline-run-*` to disk), then `wandb sync <run-dir>` from a node that *does* have egress (login/DTN node) — that step needs egress **and** the credential.

4. **Keep wandb state off the home quota.** By default wandb scatters into `~/.cache/wandb`, `~/.config/wandb`, and `./wandb`. Point it at large storage (env vars, inherited via `--export=ALL` or set in-script):

   ```bash
   export WANDB_DIR=/large/fs/<user>          # run dirs → $WANDB_DIR/wandb/
   export WANDB_CACHE_DIR=/large/fs/<user>/.wandb-cache
   export WANDB_DATA_DIR=/large/fs/<user>/.wandb-data
   export WANDB_CONFIG_DIR=/large/fs/<user>/.wandb-config
   ```

   Verify nothing leaked: after a run, `find ~/.cache/wandb ~/.config/wandb ~/wandb 2>/dev/null` should be empty.

## Diagnostic preamble (worth it on any new setup)

Make failed assumptions show at the TOP of the log, not as a cryptic error 50 lines down:

```bash
set -euo pipefail
echo "host  : $(hostname)"
echo "flags : [$-]   (no 'i' = non-interactive)"
echo "uv    : $(command -v uv || echo 'NOT FOUND — fix PATH')"
uv --version
echo "cache : $(uv cache dir)"
echo "CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-<unset>}"   # "0" = ONE gpu (index 0), NOT zero
```

## Robustness details

- **Locate sibling files with `$SLURM_SUBMIT_DIR`, not `$0`.** Slurm runs a *copy* of the script from a spool dir, so `dirname "$0"` is wrong. `source "${SLURM_SUBMIT_DIR:-$(pwd)}/common.sh"`.
- **`module` / `conda` are shell functions** injected by `/etc/profile.d/*` at login — absent in jobs. Re-source explicitly: `source /etc/profile.d/lmod.sh && module load <x>`, or `source <conda>/etc/profile.d/conda.sh`. Note: **PyTorch does NOT need a CUDA module** — wheels bundle their own runtime; only the driver (`libcuda.so`, always present on GPU nodes) matters.
- **`--export`** controls what env crosses into the job: `ALL` (default) copies your submit environment; `NONE` gives a clean slate. A well-built script (explicit PATH) survives `--export=NONE` — a good robustness test.
- **Don't hardcode `CUDA_VISIBLE_DEVICES`.** Slurm sets and *remaps* it (your allocated card always appears as `0`); overriding it on a shared node can point at another user's GPU.

## Case studies (real failures → root cause → fix)

1. **`uv: command not found` in the job, fine interactively.** Non-interactive shell skipped `~/.bashrc`. → `export PATH="$HOME/.local/bin:$PATH"`.
2. **`Permission denied` creating the cache dir.** Cache path pointed at a non-existent/placeholder location (e.g. an unset `$GROUP` → `/ocean/projects/_groupname_/...`). → fix the path; auto-detect or hardcode; `mkdir -p` and check `[ -w ]` up front so it fails loudly.
3. **`torch ... cuda avail : False` on a healthy GPU.** uv pulled `torch+cu130` (CUDA 13.0) but the driver was 560/CUDA 12.6 → major-version mismatch. → pin `cu126` (above). `module load cuda` does **not** help.
4. **Pinning torch "didn't work" — same version reappeared.** uv **reused the cached PEP 723 env** (env-var change isn't part of its cache key). → change the script's declared deps (the index pin does this) and/or `uv run --refresh-package torch ...`.
5. **`rsync: command not found` to the cluster.** The *remote* end ran in a non-login/non-interactive shell on the **login node**, where `rsync` wasn't on PATH. → use the **Data Transfer Node** host, `--rsync-path=/full/path/rsync`, or `scp -r` / `tar | ssh`.
6. **"wandb cloud UNREACHABLE from compute node" — but it wasn't.** Egress check used `curl -sSf https://api.wandb.ai/`; the root path returns `404`, and `-f` turned that successful connection into a non-zero exit → false negative that wrongly concluded "compute nodes are firewalled, must use offline+sync". Compounded by no credential, so `wandb.init` was skipped and egress was never actually exercised. → test reachability by status code (not `-f`), and confirm with a real online `wandb.init()` once a credential exists.

## How to test

- **Free non-login/non-interactive proxy:** `ssh <host> '<cmd>'` runs in the same shell class as sbatch (no GPU/SU burned). Great for checking PATH/config resolution: `ssh host 'export PATH=$HOME/.local/bin:$PATH; unset UV_CACHE_DIR; uv cache dir'`.
- **Verify `uv.toml` landed in a real job:** the trap is that an exported `UV_CACHE_DIR` masks the file (env beats uv.toml). A valid test must `unset UV_CACHE_DIR` first, confirm `env | grep UV_` is empty, then `uv cache dir` and `uv -v cache dir 2>&1 | grep -i config` (look for "Found user configuration").
- **Submit cheapest first**, escalate: hello-world → env/egress probe → editable-dep → GPU. Don't spend GPU SUs until the CPU-side passes. Check with `squeue --me`; audit what actually ran (partition/GPUs charged) with `sacct -j <id> --format=JobID,Partition,NodeList,AllocTRES%40,State`.

## When Applying This Skill

1. **Put `uv` on PATH explicitly** — the one non-negotiable line. Confirm the install dir (`~/.local/bin` vs `~/.cargo/bin`).
2. **Relocate the cache** to large storage via `~/.config/uv/uv.toml` if any install is non-trivial; skip for throwaway one-liners.
3. **GPU + torch?** Read `nvidia-smi`, pin the matching `cuXXX` index, and `assert torch.cuda.is_available()`.
4. **Source siblings via `$SLURM_SUBMIT_DIR`**, re-source `module`/`conda` only if actually needed.
5. **Add the diagnostic preamble** on any new cluster/account; strip it once the pipeline is trusted.
6. **Match resources to the allocation** — verify partition access (some grants are GPU-only); request the minimum (you can't request 0 GPUs on a GPU-shared partition).
7. **Test in the hostile shell**, not just interactively — `ssh host 'cmd'` or a tiny sbatch probe, with env vars unset where you mean to test files.
