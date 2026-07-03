"""registry — walk-up YAML registry mechanism shared by `art` and `run`.

This is a LIBRARY, imported (not run) by the sibling PEP-723 tools in this dir. It carries the
shared convention only — *walk cwd up for a `.<x>.yaml`, look up a keyed entry, resolve its `dir`
relative to the yaml (cwd-independent), fail loud, honor `--config`/env* — and knows nothing about
any tool's target (HF repo, ssh remote); each tool layers that on top. Its deps (pyyaml) come from
the importing script's own `/// script` metadata block, so this file declares none.

Import it with a symlink-robust idiom, since the tools are invoked via `~/.local/bin/` symlinks
(sys.path[0] would be the symlink dir, which has no registry.py):

    import sys; from pathlib import Path
    sys.path.insert(0, str(Path(__file__).resolve().parent))  # -> real dotfiles/bin, not the symlink
    import registry
"""
import os
import sys
from pathlib import Path

import yaml


def find_config(filename, env_var, argv):
    """Path to the nearest <filename> walking cwd upward. `--config <path>` (consumed in place
    from argv) or $<env_var> override the search. Fail-loud if nothing resolves / the override
    is not a file."""
    override = os.environ.get(env_var)
    if "--config" in argv:
        i = argv.index("--config")
        override = argv[i + 1]
        del argv[i:i + 2]
    if override:
        p = Path(override).expanduser()
        if not p.is_file():
            sys.exit(f"registry: --config/${env_var} is not a file: {p}")
        return p
    for base in (Path.cwd(), *Path.cwd().parents):
        p = base / filename
        if p.is_file():
            return p
    sys.exit(f"registry: no {filename} found from cwd upward (set --config or ${env_var})")


def entry(cfg_path, key, label):
    """The spec[key] dict from cfg_path; fail-loud if the key is absent. Target/echo formatting
    (which repo, which host) stays in the calling tool — this only proves the key exists."""
    spec = yaml.safe_load(cfg_path.read_text()) or {}
    if key not in spec:
        sys.exit(f"{label}: {key!r} not in {cfg_path} (have: {', '.join(spec) or 'none'})")
    return spec[key]


def resolve_dir(cfg_path, e):
    """`dir` resolved relative to the yaml → cwd-independent absolute path."""
    return (cfg_path.parent / e["dir"]).resolve()
