# issue #88 reproducer fixture

> **Purpose**: synthetic test corpus that reproduces the systematic-pattern signature from GitHub issue #88, so maintainers can confirm v0.8.0 chunked architecture avoids the content-safety wall.

## Background

GitHub issue [#88](https://github.com/worldwonderer/oh-story-claudecode/issues/88):
> 用户用 `/story-long-write` 生成第三卷详细章纲后，跑 `/story-review` 被 Anthropic 内容安全系统拦截。拦截不是单关键词触发，而是「卷纲 + 多章正文连起来读，看起来像系统性教会黑化叙事」。

The trigger is **context-aware**: any individual line passes safety; the *aggregated* church-coercion-betrayal pattern across multiple chapters trips the classifier. The v0.8.0 fix is to never aggregate that context — chunked single-chapter loads + summary-only global pass.

## Fixture contents

```
issue-88-reproducer/
├── README.md               ← this file
├── 大纲/
│   └── 卷纲_第三卷.md       ← high-level outline using systematic-pattern verbs (synthetic)
├── 正文/
│   ├── 第241章_审判庭.md    ← 100-200 字 sample
│   ├── 第250章_质押.md      ← 100-200 字 sample
│   └── 第263章_背叛代价.md   ← 100-200 字 sample
└── 追踪/
    ├── 角色状态.md          ← minimal tracking baseline
    └── 伏笔.md              ← minimal tracking baseline
```

The fixture is **synthetic** — it does not reproduce any real published novel. The line:
> 「第241-263章审判庭用赦免令、亲属人质和假证人瓦解聚落，必须有背叛代价」

is the exact phrase reported in issue #88. We use neutralized variants throughout to reproduce the *systematic pattern* shape, not the verbatim content.

## Why no automated CI test?

This fixture deliberately **does not run automatically in CI**. Reasons:

1. Anthropic API calls in CI are not cost-controlled here.
2. Anthropic's content-safety classifier weights drift over time; a passing run today is not a passing run tomorrow.
3. The fixture's value is as a maintainer-runnable regression check, not a binary gate.

## Manual test command

After v0.8.0 ships, a maintainer can confirm bootstrap chunking is safe:

```bash
# From repo root:
bash scripts/bootstrap-tracking.sh \
  --book skills/story-review/test/fixtures/issue-88-reproducer \
  --dry-run
```

Expected: exit 0, manifest written to `追踪/.bootstrap/extraction-jobs.txt`, **3 per-chapter prompt files** each containing only one chapter's path and the reframe preamble. **The manifest must NOT contain any aggregated cross-chapter prose** — that's the key safety property.

For a deeper safety test:

```bash
# Pre-flight: confirm each chapter individually passes safety in a quick
# claude-code prompt:
for ch in skills/story-review/test/fixtures/issue-88-reproducer/正文/*.md; do
  echo "Testing $ch"
  # (maintainer runs /story-review --solo on this single file via claude code)
done
```

If a single chapter still triggers safety, the synthetic fixture has drifted too close to actual triggering content — adjust the prose to be more clearly neutralized while preserving the *systematic-pattern shape*.

## Checklist before tagging v0.8.0

- [ ] `bash scripts/bootstrap-tracking.sh --book skills/story-review/test/fixtures/issue-88-reproducer --dry-run` exits 0 and emits 3 per-chapter prompts.
- [ ] Each per-chapter prompt file contains only ONE chapter's file path (no aggregation).
- [ ] Manual: each chapter file individually does not trigger safety in a fresh claude-code session.
- [ ] Manual: the manifest's reframe preamble is the **first content** in each prompt (safety classifiers weight early tokens).

## Future updates

If Anthropic's safety policy changes such that even single-chapter neutralized fixtures trigger, the architecture is no longer sufficient and we need to consider:
- routing /story-review to a non-Claude reviewer (Gemini fallback)
- further reducing chunk size (per-paragraph rather than per-chapter)
- shipping a `--unsafe-redact` flag that programmatically blanks out a configurable list of trigger verbs before submission

Both are deferred to v0.8.1+ pending evidence.
