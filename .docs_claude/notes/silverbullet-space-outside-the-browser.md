# What a SilverBullet space looks like from outside the browser

Why editing `~/worklog` in nvim works at all, what the browser knows that the
filesystem does not, and why `scp://` lost to `ssh` for `sbj`. Measured against
SilverBullet 2.10.0 on jke-desktop.

## The disk is the whole truth — there is no server-side index

The data dir holds only `spaces.json`, `users.json`, `.silverbullet.session.json`. No
database, no cache, nothing to invalidate:

| step | result |
|---|---|
| `GET /.fs/sbapi-test.md` | `version one from disk` |
| overwrite the file on disk, no restart | — |
| same `GET` again | `version TWO, edited on disk` |
| type in laptop nvim, `:w` | — |
| same `GET` again | `version THREE, typed in laptop nvim` |

So an external editor needs no coordination with the server: it reads files per request.
The only thing that must notice a change is an already-open browser tab, which SB
handles by watching the folder.

The `/.fs` endpoints need auth once the space is not public — a bare `GET` returns 401.
`POST /.auth` with `username`/`password` (from `~/.config/silverbullet/admin-password`)
sets a cookie. The docs-site recipe in the `silverbullet` skill omits this because
`silverbullet.md` is public.

## Some pages SilverBullet serves do not exist on disk

`GET /.fs` lists `Library/Std/APIs/Action Button.md` and ~100 more siblings.
`ls ~/worklog/Library` → **no such directory**. They are baked into the binary.

This is the hard ceiling on any file-based workflow: nvim, `rg`, and telescope can
*never* see those pages. Anything that greps the space for a definition and comes up
empty may be looking at a virtual page.

## `index.md` is not navigable from a text editor

It contains no wikilinks at all — it is Space Lua:

```markdown
${query[[ from j = index.pages(config.get("journal.tag")) order by j.date desc ... ]]}
```

Dynamic, server-evaluated. Whatever an editor does with a space, it cannot reproduce the
index page, the task aggregation, or the tag picker. Wikilink *following* is
reproducible; the query layer is not.

## Wikilinks are absolute from the space root

Per `silverbullet.md/.fs/Link.md`, and confirmed in place: `Journal/2026-08-20.md` links
`[[vim dump aug20]]`, which resolves to the **root** page, not `Journal/vim dump
aug20.md`. Forms, all seven parsed by `nvim/lua/custom/sbnav.lua`:

| form | meaning |
|---|---|
| `[[page]]` | absolute from root, `.md` implicit |
| `[[page\|Alias]]` | alias after `\|` |
| `[[Page#Header]]` | anchor; the header text may itself contain `#`, so the core ends at the *first* `#` or `@` |
| `[[Page@L12c42]]` / `[[Page@123]]` | line/col (1-based), or nth character (0-based) |
| `[[^Library/Std]]` | meta page; same target as without `^` |
| `[[#Header]]` | empty core = current page |

Plain `gf` cannot follow these: `'isfname'` splits a target at its spaces, so a page
named `vim dump aug20` yields `E447: Can't find file "dump"`.

## Why `sbj` runs nvim over ssh instead of editing `scp://` paths

netrw's `scp://` genuinely works — round-trip verified — but it is not a filesystem:

| | `scp://` | ssh + remote nvim |
|---|---|---|
| telescope `find_files` | stack trace at `pickers.lua:664` (spawns `fd` with the URL as a cwd) | 7/7 pages |
| telescope `live_grep` | impossible natively | 1/1, live per keystroke |
| `:w` | `:!scp -q '<temp>' 'host:/path'` — **whole-file replace**, no merge | ordinary local write |
| `spell` on a page | `0` — netrw sets `filetype` without firing `FileType`, so the prose-spell rule never runs | `1`, free |
| page names with spaces | literal spaces work; **`%20` yields an empty buffer** | n/a |

The `scp://` route's one advantage is that it uses the *laptop's* config. That mostly
evaporates because both machines run this same repo — but it does mean the ssh route
carries a sync obligation: `zg` in a remote nvim writes the **desktop's**
`spell/en.utf-8.add`, so new words need a commit and push to reach the laptop.

A `scp://` implementation of all of the above (including ssh-backed telescope pickers)
was written and verified, then deliberately not installed, to avoid keeping two code
paths for one workflow.
