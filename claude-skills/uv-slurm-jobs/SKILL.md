---
name: uv-slurm-jobs
description: Write and debug Slurm/sbatch (or any non-interactive) job scripts that use uv on HPC clusters, including getting Weights & Biases (wandb) working in batch jobs. Use when creating batch scripts that call `uv run`/`uv pip`, when a command works in an interactive shell but fails under the scheduler, or when diagnosing "uv: command not found", disk-quota errors, torch "cuda avail: False", or wandb auth/egress failures inside a job.
argument-hint: [cluster name or what the job should run]
allowed-tools: Read, Write, Edit, Bash(sbatch:*), Bash(squeue:*), Bash(sacct:*), Bash(scontrol:*), Bash(scancel:*), Bash(sinfo:*), Bash(tail:*), Bash(uv:*), Bash(ssh:*), Bash(rsync:*), Bash(scp:*)
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

## From a Python script → an sbatch script (the decision checklist)

Turning any `train.py`/`run.py` into a batch job is a fixed interrogation — read the script **and its `pyproject.toml`**, answer each question, map to directives. Don't guess resources; derive them from what the script does.

| Inspect the script for… | If yes → | sbatch / env consequence |
|---|---|---|
| `torch`/`jax` + `.cuda()`/`device=`/`.to(...)` | needs a GPU | `-p <gpu-partition> --gpus=<type>:<n>`; **pin the CUDA wheel to the driver** |
| large data reads / checkpoint writes | needs scratch/project FS | paths on ocean/scratch, never `$HOME`; `mkdir -p` outputs **before** the run (configs often assert the dir exists) |
| `argparse` / config files | pass them through | append after the entrypoint: `uv run script.py --cfg a.yaml key=val` |
| wandb / tensorboard logging | creds + egress + dir | `~/.netrc` or `WANDB_API_KEY`; `WANDB_DIR` off `$HOME` (see wandb section) |
| editable sibling deps (`uv add --editable ../pkg`) | bind **and sync** them | each sibling on a commit compatible with the code you run — a stale/detached HEAD throws `ImportError` on a renamed symbol or a file added in an unpulled commit |
| multi-GB install (torch, isaac) | cache + walltime | uv cache on big FS (`uv.toml`); size `-t` for the first install; pre-warm the `.venv` on a CPU node so the GPU job doesn't pay SU for it |
| host glibc too old for the wheels (`manylinux_2_35`) | containerize | wrap the `uv run` in `singularity exec --nv … bash -c '…'` — see the **apptainer-images** skill |

Then size from actual need (1 GPU is the floor; shortest honest walltime — see the run loop), add the diagnostic preamble, and **submit cheapest-first**: a 1-step / 1-frame smoke (and, for editable workspaces, a CPU-side `python -c "import yourpkg"` preflight) before the full job.

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

## Requesting GPU resources — the formula (PSC Bridges-2)

The ask is `-p <partition> --gpus=<type>:<n> -N <x> -t <walltime>`. What's *valid* for `n`
depends on whether you take **whole nodes** or a **fraction of one**.

**Whole-node `GPU` partition** — you always occupy entire nodes, so `n` (the **total** GPUs for
the job) must be a multiple of 8:

```
sbatch -p GPU --gpus=<type>:<n> -N <x> <jobname>
```

- `n` = total GPUs = 8, 16, 24, or 32 (i.e. 8 × nodes). For the DGX-2 use `n=16` and never ask
  for more than one node.
- `type` = `v100-16` or `v100-32` (also `h100-80`, `l40s-48`).
- `x` = nodes, 1–4. Omit `-N` for a single node (defaults to 1).
- Valid single-node requests:
  - `--gpus=h100-80:8`   one H100-80 node
  - `--gpus=l40s-48:8`   one L40S-48 node
  - `--gpus=v100-32:16`  the DGX-2
  - `--gpus=v100-32:8`   one V100-32 Tesla node
  - `--gpus=v100-16:8`   one Volta node

**Fractional `GPU-shared` / `GPU-small`** — for anything that does NOT need a whole node (dev,
smoke tests, single-GPU training), request `--gpus=<type>:1..4`. Here `n` is **not** constrained to
multiples of 8: you share the node and are billed per GPU. `GPU-small` is a separate, lighter queue
for short single-node jobs (`DefaultTime=01:00:00`) and usually schedules fastest. 1 GPU is the
floor — you cannot request 0 on a GPU partition, and you can't shrink the count below 1, so the
only knobs left for faster scheduling are **partition** and **walltime** (see case study 7).

Pick a `type` that is actually free *now*, not one that is fully `alloc`:

```
sinfo -p GPU-shared,GPU-small,GPU -o "%.12P %.6t %.5D %.20G %.15C" | sort -k2
# state mix/idle = capacity available;  %C = CPUs A/I/O/T (Idle>0 means room)
scontrol show partition GPU-small | grep -iE "DefaultTime|MaxTime|MaxNodes|TRES"
```

**Gauge GPU contention before committing — idle CPUs ≠ free GPUs.** A node in `mix` can show idle *cores* in `%C` yet have **every GPU already allocated**, so your `--gpus` request still won't schedule there. `%C` is CPU-only; for the GPU picture, count usage and competition for the exact SKU you want:

```
sinfo -o "%n %t %G" | grep l40s                              # nodes of that type + state (down/mix/alloc/idle)
squeue -p GPU-shared -t RUNNING  -o "%b" | grep -c "l40s"    # that GPU type in use right now
squeue -p GPU-shared -t PENDING  -o "%b" | grep -c "l40s"    # jobs already queued for it = your competition
```

## Spawn → follow → audit (the run loop)

1. **Submit and capture the id in one shot** — `--parsable` prints only the number (the id's source
   of truth is this return, *not* the log):

   ```bash
   jobid=$(sbatch --parsable job.sbatch)   # e.g. 41642995
   ```

2. **Watch the queue until it runs:**

   ```bash
   squeue -j "$jobid" -o "%.12i %.12P %.8T %.10M %R"   # PD→R;  %R = pending reason
   scontrol show job "$jobid"                          # full detail when stuck
   squeue -j "$jobid" --start                          # scheduler's ETA (START_TIME), if planned
   ```
   Pending `Reason`: `(Priority)` = behind higher-priority jobs; `(Resources)` = next in line, waiting for hardware to free; `(None)` = about to start; `(AssocGrpGRES)`/`(QOSMax…)`/`(Dependency)` = a limit/block, not raw contention.
   **ETA is a soft estimate, not a promise.** `--start` / `scontrol`'s `StartTime` comes from the *backfill* scheduler and assumes every running job uses its full walltime — so it's usually **pessimistic** (you often start earlier), it **moves** every scheduling cycle (a higher-priority arrival pushes it later; early finishes pull it earlier), and it's **`N/A`** until the scheduler plans the job or whenever a dependency/QOS/association limit makes timing indeterminate. A multi-day ETA on a scarce SKU (e.g. an RT-core-only GPU like L40S) is the cue to **consolidate** — submit the real job rather than a test-then-real two-wait sequence — or pick a less contended resource.

3. **Follow the streams live** — Slurm flushes `-o`/`-e` *as the job runs*:

   ```bash
   tail -F job_${jobid}.out job_${jobid}.err   # -F (not -f): files don't exist until it starts
   ```
   Use `-F` because the log is created at job start. For Python, run `python -u` (or
   `PYTHONUNBUFFERED=1`) or lines sit in stdio's block buffer and arrive in one chunk at exit;
   bash `echo` already flushes per line. For an **unattended** follow that ends itself, tail in the
   background and stop when the job leaves the queue:

   ```bash
   tail -F job_${jobid}.out & tp=$!
   while squeue -h -j "$jobid" 2>/dev/null | grep -q .; do sleep 3; done
   kill "$tp"
   ```
   Tail *raw*, or grep an alternation that includes failure signatures
   (`Traceback|Error|FAILED|OOM|Killed`) as well as progress — a filter that matches only the
   success marker stays silent through a crash, and silence looks identical to "still running."

4. **Audit what actually ran / was charged** (do this every time — it's how you catch a job that
   silently landed on the wrong partition or grabbed the wrong GPU count):

   ```bash
   sacct -j "$jobid" --format=JobID,Partition,NodeList,AllocTRES%32,State,Elapsed,ExitCode
   ```
   `AllocTRES` shows the GPUs + `billing` you were charged; `State=COMPLETED ExitCode=0:0` is
   success, `FAILED`/`TIMEOUT`/`OUT_OF_MEMORY` name the fix.

5. **Cancel:** `scancel "$jobid"`.

## Case studies (real failures → root cause → fix)

1. **`uv: command not found` in the job, fine interactively.** Non-interactive shell skipped `~/.bashrc`. → `export PATH="$HOME/.local/bin:$PATH"`.
2. **`Permission denied` creating the cache dir.** Cache path pointed at a non-existent/placeholder location (e.g. an unset `$GROUP` → `/ocean/projects/_groupname_/...`). → fix the path; auto-detect or hardcode; `mkdir -p` and check `[ -w ]` up front so it fails loudly.
3. **`torch ... cuda avail : False` on a healthy GPU.** uv pulled `torch+cu130` (CUDA 13.0) but the driver was 560/CUDA 12.6 → major-version mismatch. → pin `cu126` (above). `module load cuda` does **not** help.
4. **Pinning torch "didn't work" — same version reappeared.** uv **reused the cached PEP 723 env** (env-var change isn't part of its cache key). → change the script's declared deps (the index pin does this) and/or `uv run --refresh-package torch ...`.
5. **`rsync: command not found` to the cluster.** The *remote* end ran in a non-login/non-interactive shell on the **login node**, where `rsync` wasn't on PATH. → use the **Data Transfer Node** host, `--rsync-path=/full/path/rsync`, or `scp -r` / `tar | ssh`.
6. **"wandb cloud UNREACHABLE from compute node" — but it wasn't.** Egress check used `curl -sSf https://api.wandb.ai/`; the root path returns `404`, and `-f` turned that successful connection into a non-zero exit → false negative that wrongly concluded "compute nodes are firewalled, must use offline+sync". Compounded by no credential, so `wandb.init` was skipped and egress was never actually exercised. → test reachability by status code (not `-f`), and confirm with a real online `wandb.init()` once a credential exists.
7. **Job stuck `PENDING (Priority)`; a smaller/shorter request ran in seconds.** A hello-world asked
   for `-p GPU-shared --gpus=v100-16:1 -t 0:03:00` and sat behind higher-priority jobs
   (`Reason=Priority`). Resubmitting to the lighter **`GPU-small`** queue with `--gpus=v100-32:1
   -t 0:02:00` flipped the reason to `(None)` and it scheduled immediately — `sacct` confirmed
   `AllocTRES=…gres/gpu:v100-32=1,billing=5`, `COMPLETED 0:0` in 36 s. → 1 GPU is the floor, so when
   a tiny job won't schedule the levers are **partition** (GPU-small ≫ GPU-shared for short jobs) and
   **walltime** (shorter backfills into gaps), plus picking a `type` that `sinfo` shows as `mix`/idle
   rather than fully `alloc`. Corollary: a **GPU-only allocation** (e.g. PSC `cis260205p` has no
   RM/CPU access) must grab ≥1 GPU even for a trivial logging job — there is no free CPU partition to
   fall back to.

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
8. **Run the loop**: `jobid=$(sbatch --parsable …)` → `squeue -j $jobid` until `R` → `tail -F *_$jobid.out *_$jobid.err` (live) → `sacct -j $jobid …` to confirm partition/GPUs/exit. If it won't schedule, try `GPU-small` and a shorter `-t` before anything else.
