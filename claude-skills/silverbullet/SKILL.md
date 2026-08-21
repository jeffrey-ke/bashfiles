---
name: silverbullet
description: Look up SilverBullet features in the official docs or community forum, and write/extend research log entries in the local worklog space. Use when the user asks how to do something in SilverBullet (frontmatter, tags, queries, Space Lua, templates, tasks, journal, config), says "write a log" / "add this to a log", asks "what tags would you recommend?", or hits a SilverBullet error.
argument-hint: a question, a topic to log, or "tags" to get tag suggestions
allowed-tools: Read, Write, Edit, Bash(curl:*), Bash(jq:*), Bash(sb-up:*), Bash(ls:*), Bash(rg:*), Bash(grep:*), Bash(strings:*), Bash(silverbullet:*)
---

# SilverBullet: docs lookup + research log

Local space: **`~/worklog`** (plain `.md` on disk, served at `127.0.0.1:3030`, started by `sb-up`).
Edit files directly — the server watches the folder and pushes changes to open browsers.

## Retrieval

Two JSON/raw endpoints. Prefer these over `WebFetch` — exact content, no HTML shell.
The docs site is itself a SilverBullet space; `/.fs` is its file API.

```bash
# List all 298 doc pages (once, to locate a topic)
curl -s https://silverbullet.md/.fs | jq -r '.[].name' | sed 's/\.md$//' | sort

# Fetch one page as raw markdown — URL-encode spaces as %20
curl -s 'https://silverbullet.md/.fs/Frontmatter.md'
curl -s 'https://silverbullet.md/.fs/Space%20Lua.md'

# Forum search (Discourse), then read a topic by id
curl -s 'https://community.silverbullet.md/search.json?q=<terms>' \
  | jq -r '.topics[:8] | .[] | "\(.id)  \(.title)"'
curl -s 'https://community.silverbullet.md/t/<id>.json' \
  | jq -r '.post_stream.posts[].cooked'
```

Traps: plain `https://silverbullet.md/<Page>.md` returns the SPA HTML shell, **not** markdown —
the `/.fs/` prefix is required. `sitemap.xml` and `index.json` also return the shell.
Forum `cooked` fields are HTML.

**Docs first for how-it-works; forum for "is this possible / why is mine broken."**
Forum categories worth scoping to: `lua`, `tricks-techniques`, `plugs-libraries`, `trouble`.

## Version skew — the docs site is *edge*, not your install

`silverbullet.md` is a live space tracking the newest upstream release. It is the right source for
"how does X work upstream" and the wrong source for "what is bound / available **here**."
Anything version-sensitive — **keybinds, command names, config schema, Lua APIs** — must be
checked against the local binary before answering. Ground truth is the compiled plug manifest:

```bash
silverbullet --version                  # e.g. 2.10.0-0-g2b2a7c71-2026-07-28T12-40-06Z

# What key is actually bound to a command (manifest carries key + mac separately)
strings -n 6 ~/.local/bin/silverbullet | grep -a 'Navigate: Home' | cut -c1-1200
#   ...navigateHome:{...command:{name:"Navigate: Home",key:"Ctrl-Shift-h",mac:"Cmd-Shift-h"...

# Does a prefix/binding exist in this build at all?
strings -n 4 ~/.local/bin/silverbullet | grep -c 'Ctrl-g'    # 0 in 2.10.0 -> feature is newer
strings -n 4 ~/.local/bin/silverbullet | grep -c 'Ctrl-q'    # 8 -> the grep itself works

# Enumerate commands present in this build
strings -n 6 ~/.local/bin/silverbullet | grep -oE '"(Navigate|Page|Journal|Task):[^"]{0,40}"' | sort -u
```

`grep -abo <string> ~/.local/bin/silverbullet` gives byte offsets; `dd bs=1 skip=<off-400> count=900`
dumps the surrounding manifest when the line is too long to read. Never `grep -o '.\{0,300\}X.\{0,300\}'`
on the binary — ripgrep bails with a complexity error.

Known skew (as of 2026-08-20, local install 2.10.0):

| Task | Docs site (edge) | 2.10.0 (local) |
|---|---|---|
| Go to index/home page | `Ctrl-g h`, `Ctrl-g` navigational prefix | `Ctrl-Shift-h` / `Cmd-Shift-h`, command `Navigate: Home`; no `Ctrl-g` prefix |

Rules:
- **Quote the manifest, not the docs, when the user asks what a key does on their machine.** State the
  version you checked.
- Don't infer per-OS behavior from the docs' modifier-key section. `key` vs `mac` in the manifest is
  the only answer; `Mod` aliasing is about *authoring* shortcuts, not about what's already bound.
- Cheaper non-shell check the user can run: the Command Palette lists each command's assigned
  shortcut to its right. The 🏠 top-bar button runs `Navigate: Home` (see `actionButtons` config).
- To backport an edge binding instead of upgrading, `command.update { name = "...", key = "..." }`
  in a `space-lua` block.

## Doc map

| Need | Page |
|---|---|
| Orientation, first steps | `Getting Started`, `Manual`, `Best Practices`, `Knowledge Base` |
| Page-level attributes, tags | `Frontmatter`, `Attribute`, `Meta Page` |
| Syntax, callouts, embeds | `Markdown/Basics`, `Markdown/Extensions`, `Markdown/Admonition`, `Document` |
| Tasks, checkboxes | `Task`, `Guide/Task Management` |
| Daily notes | `Journal` |
| Scripting, queries | `Space Lua`, `Space Lua/Standard Library`, `Space Lua/Integrated Query`, `Object` |
| Reusable content | `Template`, `Library` |
| Search, navigation | `Full Text Search`, `Tag Picker` |
| Appearance, keys, config | `Configuration Manager`, `Keyboard Shortcuts`, `Page Decorations`, `Space Style` |
| Vim mode, custom vim keybinds | `Vim` |
| Ops | `Install`, `Authentication`, `TLS`, `CLI`, `Troubleshooting` |

## Custom Vim keybinds

SilverBullet's Vim mode (`Editor: Toggle Vim Mode`) is a real CodeMirror vim implementation, not
just a few shortcuts — it takes ex commands directly (`:imap jj <Esc>`) and can be configured
persistently via `config.set { vim = {...} }` in a `space-lua` block in `CONFIG` (see the `Vim`
doc page). Supported keys: `map`/`noremap`/`imap`/`nmap`/`vmap`/etc. (mode variants), `unmap`,
and `commands` (bind ex commands to SilverBullet commands). Confirmed present in the local 2.10.0
binary via `strings ~/.local/bin/silverbullet | grep -a '"noremap"'` — the CodeMirror vim addon's
ex-command table (`map`, `nmap`, `noremap`, `nnoremap`, `unmap`, `mapclear`, ...) is compiled in.

```lua
config.set {
  vim = {
    unmap = { "<Space>" },              -- a bare key must be freed before it can prefix a sequence
    noremap = {
      { map = "<Space>p", to = "a<Space><Esc>", mode = "normal" },
    },
  }
}
```

Reload with `Editor: Vim: Load Vim Config` (or restart the client) to pick up `CONFIG` changes
without a full page reload.

Prefer this over emulating vim behavior with a synthetic `command.define` + `editor.insertAtCursor`:
the latter has no modal cursor semantics, so e.g. `a<Space><Esc>` (append *after* cursor) is not the
same as `editor.insertAtCursor(" ")` (insert *at* cursor) — a real `noremap` reproduces the exact
keystrokes and gets vim's semantics for free.

Gotcha: several single keys (e.g. bare `<Space>`, which page-scrolls) are bound by default. Reusing
one as a multi-key leader prefix requires `unmap`-ping the bare key first, or the prefix sequence
never fires.

## Writing a log

Journal convention is `Journal/YYYY-MM-DD` (built in, not a plug; `Journal: Today` = `Ctrl-q j`).
Use it for dated entries; use a topic page for anything that outlives the day.

Get the date from `date +%F` — never guess it.

```markdown
---
tags: worklog <topic> <topic>
---
# <What this was about>

## Context
Why this came up — the question or symptom.

## What I found
Findings, with `file:line` pointers and commands actually run.

## Next
- [ ] open thread
```

Rules:
- **"add this to a log"** → append to today's `Journal/YYYY-MM-DD` (or the named page) with `Edit`;
  create it only if missing. Never overwrite an existing entry.
- Link topic pages as `[[Page Name]]` from the journal entry — SilverBullet shows the reverse
  under Linked Mentions on that page, so linking *is* the index. Prefer a link over a duplicate.
- Screenshots/attachments: copy into `~/worklog/` (subfolders fine) and embed `![](assets/x.png)`.
- Absolute desktop paths: paste the snippet or a screenshot. A `file:///...` link resolves against
  the *laptop's* browser and will fail.

## Recommending tags

`tags:` in frontmatter prefers **space-separated bare words on one line** (`tags: worklog nvim`).
Inline `#hashtags` in the body work too and are queryable the same way. Reserved: `name`
(don't set), `displayName`, `aliases`.

When asked "what tags would you recommend?":

1. Read existing tags before inventing any — reuse beats coining:
   `rg -N '^tags:' ~/worklog --no-heading | tr ' ' '\n' | sort | uniq -c | sort -rn`
2. Suggest 2–4: one **kind** (`worklog`, `note`, `debug`, `decision`), one or two **subjects**
   (`nvim`, `tmux`, `silverbullet`), optionally one **project**.
3. Singular, lowercase, no punctuation. Reuse an existing near-match rather than adding a synonym.
4. Say which are existing vs new, and why.

## When applying this skill

1. Docs or forum? Docs for mechanics; forum for feasibility, bugs, and community recipes.
2. Fetch via `/.fs/` — don't guess API syntax from memory, and quote what the page says.
3. Writing: new topic page, or append to today's journal? Default to appending.
4. Check existing tags before proposing new ones.
5. State the page/topic URL you drew from, so the log entry is traceable.
