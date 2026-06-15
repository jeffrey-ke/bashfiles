# `:St!` partial hunk commit fix

**Symptom:** `:St!` correctly staged only the visually selected lines (confirmed via `git diff --cached`), but `git show HEAD` after committing contained the whole file's changes.

**Root cause:** `on_write` was passing `-- <path>` to `git commit`. Per git docs, `git commit -- <path>` does not filter which staged content gets committed — it auto-stages the working tree version of `<path>` first, overwriting the partial staging. The whole file was being silently re-staged before every commit.

## Change

**`lua/custom/stage_commit.lua`** — removed `-- <restrict_path>` from the commit args in `on_write`:

```lua
-- before
local args = { 'commit', '-F', tempfile }
if M.popup.restrict_path and M.popup.restrict_path ~= '' then
    table.insert(args, '--')
    table.insert(args, M.popup.restrict_path)
end

-- after
local args = { 'commit', '-F', tempfile }
```

The staging step (gitsigns) already controls exactly what is in the index. The `restrict_path` field is still used by `open_commit_popup` for the `# committing only changes to:` display comment and the `staged_name_status` guard, but must not be forwarded to `git commit`.
