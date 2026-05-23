# agent-references — Canonical seed for story agents

This directory is the **canonical seed** for the reference files shipped to agent prompts. `/story-setup` (and `bash scripts/dev-setup.sh` for contributors) copies these files into a project's `.claude/agent-references/`, and the creative agent templates (story-architect / character-designer / narrative-writer / consistency-checker) resolve their `<<STORY_REF>>/X.md` placeholders against that deployed copy.

## Sibling skill copies are intentional, not drift

Several writing skills (`story-long-write`, `story-deslop`, `story-review`, `story-short-analyze`, `story-short-write`) ship their **own** copy of files like `anti-ai-writing.md`, `banned-words.md`, `quality-checklist.md`, `writing-craft.md` inside their `references/` directories.

This is intentional. Reasons:

1. **clawhub / standalone install** — A user may install only `story-long-write` via clawhub without running `/story-setup`. The skill must work standalone, so it ships its own references.
2. **Skill-specific customization** — Some skills tailor their copy for that skill's context. Example: `skills/story-short-analyze/references/quality-checklist.md` adds a "拆书定位" header and cross-references its own `material-decomposition.md`. That divergence is correct, not drift.

So sibling copies **may diverge** from the canonical here, on purpose. Don't blindly overwrite them.

## How to keep things sane

- When you update an `anti-ai-writing.md` / `banned-words.md` / `quality-checklist.md` / `writing-craft.md` rule that's broadly applicable, **decide per-file** whether the change should propagate to sibling skills or stay canonical-only.
- Run `bash scripts/check-references-canonical.sh` to see a diff report between canonical and sibling copies. The report is **advisory**, not enforced — it tells you which files have drifted so you can review whether the drift is intentional.

## `_attic/` — archived references

Files under `_attic/` are kept in the repo for reference but are not shipped to deployments.

- `_attic/plot-core-methods.md` — Was a canonical seed in v8 and earlier, but no story-setup agent template references it. The two sibling copies (`story-long-write/references/plot-core-methods.md` and `story-review/references/plot-core-methods.md`) **are** referenced by their own skills and stay live. v9 removes it from the canonical seed only.
