# macOS: slow new terminal tabs are exec latency, not the dotfiles

## Symptom

On `jke-laptop` (2026-08-11), a new Ghostty tab took 10+ seconds to show a prompt. The
obvious suspicion is that something sourced is slow. It isn't.

## What it is not

Per-file timing, all inside **one** shell so process-spawn cost isn't counted per file:

```bash
/bin/bash --norc -ic '
for f in ~/.bash_aliases ~/.functions.sh ~/.bash_prompt ~/.bash_tools ~/.bash_vars \
         ~/dotfiles/source-machine.sh; do
  printf "== %s\n" "$(basename $f)"; time source "$f"
done'
```

```
.bash_aliases 0.001s   .bash_prompt 0.009s   .bash_vars       0.001s
.functions.sh 0.001s   .bash_tools  0.096s   source-machine.sh 0.054s
```

Whole login chain warm — `/etc/profile`, `path_helper`, `/etc/bashrc`, `.bash_profile`,
`.bashrc` and all six files: **0.19s** (`bash -lic true`). There is no 10 seconds of work
in this repo's startup path.

## What it is

CrowdStrike Falcon runs here as an Endpoint Security system extension
(`com.crowdstrike.falcon.Agent.systemextension`). ES *authorizing* subscribers hold every
`exec` until the agent returns a verdict, and the verdict is cached per binary. Measured,
same command, same flags:

```
first  /bin/bash --norc -c true   → 4.50s
repeat /bin/bash --norc -c true   → 0.00s   (×3)
```

Individually timed startup commands were all 0.00s warm (`hostname`, `basename`,
`brew shellenv`, `fzf --bash`, `zoxide init`, sourcing `gitprompt.sh`). So the latency
tracks *cold execs*, not work. A new tab is a chain of distinct binaries — `login`, then
`bash`, then during rc `brew shellenv`, `zoxide init`, `fzf --bash`, `hostname`, one
`basename` per file in `machines/`, plus bash-git-prompt's `git` calls — and each one
needs its own verdict.

Falcon-as-cause is inference from the timing signature, not something the agent reports.
To confirm, in a brand-new tab run `time bash -lic true` twice: first slow + second
instant is exec-scan latency; both slow would mean it is config after all.

## Why it appeared on 2026-08-11 and not before

Until [macos-login-shell-and-machine-config-dedup.md](../plans/completed/macos-login-shell-and-machine-config-dedup.md)
this machine had no `.bash_profile`, so a login shell read **nothing** — a new tab was
instant because it did no work. Fixing that made the machine's exec-authorization cost
visible for the first time. Nothing got slower; something started happening at all.

## Consequence for this repo

On a machine with an exec-authorizing agent, the cost of a startup file is roughly the
number of *distinct programs* it runs, not the number of lines it has. Current inventory
per interactive shell:

| where | execs | reducible? |
|---|---|---|
| `source-machine.sh` | ~~8 — `hostname -s` + one `basename` per `machines/*.sh`~~ → **0** | done 2026-08-11: `${HOSTNAME%%.*}` and `${f##*/}`/`${name%.sh}`. 0.054s → 0.001s |
| `.bash_tools` | 3 — `brew shellenv`, `zoxide init`, `fzf --bash` | only by caching their output to a file, which then goes stale on upgrade |
| `.bash_prompt` | bash-git-prompt's own `git` calls | not without dropping the prompt |

Note the honest size of that win: 8 forks+execs, but only **2 distinct binaries**
(`hostname`, `basename`), and an authorizing agent caches per binary — so seven
`basename` calls are one cold verdict plus six cached hits, not seven. The steady-state
saving is the ~50ms of forking, verified as 0.054s → 0.001s. It was worth doing because
it was the only exec in the startup path that bought nothing; `brew shellenv`,
`zoxide init` and `fzf --bash` each produce output the shell actually needs, and can only
be removed by caching output that then goes stale on upgrade.

Equivalence was checked rather than assumed: old and new resolution agree for every name
in `machines/` (`tesu`, `jeffpro-3`, `br011`, `br013`, `r[0-9]+` against r033/r191/r7/r999),
for a host that matches nothing, and — feeding the new code an FQDN where the old code
would have received `hostname -s` output — for `r033.ib.bridges2.psc.edu`, `tesu.local`,
`jke-laptop.local`.
