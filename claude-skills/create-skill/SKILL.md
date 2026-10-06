---
name: create-skill
description: Creates or updates a Claude Code skill per Nuro's skill guide. Use when saving a technique, pattern, or workflow as a skill.
argument-hint: <skill-name> [description of what the skill should capture]
allowed-tools: Bash(cat ~/.claude/plugins/marketplaces/nurons-marketplace/docs/skill-guide.md), Bash(~/dotfiles/sync-skills.sh)
---

# Create a Claude Code Skill

Nuro's skill guide is the rulebook: frontmatter, description limit, layout,
`allowed-tools`, common mistakes, checklist. Follow it; don't restate it in the skill.

!`cat ~/.claude/plugins/marketplaces/nurons-marketplace/docs/skill-guide.md`

## Step 1 — Ask where it belongs

Ask before writing anything, together with any other design questions:

| Home | When | Path |
|---|---|---|
| Dotfiles | personal, cross-repo, synced across machines | `~/dotfiles/claude-skills/<name>/` |
| Monorepo | helps understand or modify Nuro monorepo code | `<area>/.claude/skills/<name>/` per the guide's decision tree |
| Marketplace | shareable cross-repo tooling or workflow | hand off to `/essentials:creating-plugin` |

## Step 2 — Write it

- Name, description, layout, and `allowed-tools` per the guide.
- `argument-hint` when the skill takes arguments.
- Lead with steps or a working recipe; imperative voice ("run X", not "you can run X").
- Scripts are self-contained; reference them by their installed path
  (`~/.claude/skills/<name>/scripts/...`), never by the dotfiles path.

## Step 3 — Install (dotfiles)

```bash
~/dotfiles/sync-skills.sh
```

It symlinks every `claude-skills/<name>/` into `~/.claude/skills/` and
`~/.codex/skills/`, skipping ones already linked. Committing to dotfiles needs
its own confirmation: that checkout usually has unrelated uncommitted work, so
stage only the skill's directory.

## Step 4 — Verify

Walk the guide's checklist, then load the skill in a fresh session:

```bash
claude -p '/<name> <a realistic request>' --max-turns 3
```

For a skill that injects command output at load time, ask the session to echo
the injected line back to confirm the command ran and its permission is covered.
