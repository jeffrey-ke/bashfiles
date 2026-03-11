---
name: create-skill
description: Create a new reusable Claude Code skill and register it for auto-discovery. Use when the user asks to save a technique, pattern, or workflow as a skill.
argument-hint: <skill-name> [description of what the skill should capture]
---

# Create a Claude Code Skill

## Process

1. **Choose a name**: kebab-case, descriptive of the capability (e.g. `visualize-se3-frames`, `fold-knowledge-into-data`)

2. **Create the skill file** at `~/dotfiles/claude-skills/<skill-name>/SKILL.md` with this structure:

```markdown
---
name: <skill-name>
description: <one-line description of when to use this skill — written for Claude, not humans>
argument-hint: <what arguments the user might pass>
---

# <Title>

<Brief explanation of the technique/pattern>

## Core Recipe

<Minimal, copy-paste-ready code or steps that accomplish the task>

## Variations

<Common adaptations, parameter choices, edge cases>

## When Applying This Skill

<Numbered checklist of decisions to make when using it>
```

3. **Symlink into auto-discovery path**:
```bash
ln -s ~/dotfiles/claude-skills/<skill-name> ~/.claude/skills/<skill-name>
```

## Skill Writing Guidelines

- The **description** field is how Claude decides whether to invoke the skill — make it specific about triggers and use cases
- The **argument-hint** tells the user what to type after the slash command
- Lead with a working **core recipe** — minimal code that solves the common case
- Include **variations** only for genuinely common alternatives, not every possibility
- Keep it concise: a skill is a recipe card, not a tutorial
- Code in skills should be self-contained snippets, not imports from the project
- Write for Claude as the reader: skills guide Claude's code generation, so frame instructions as "do this" not "you can do this"
