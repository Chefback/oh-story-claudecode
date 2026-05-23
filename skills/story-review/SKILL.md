---
name: story-review
version: 1.1.0
description: |
  多视角对抗式审查。4 个 Agent 并行 spawn（full 模式），各自从不同角度找问题，主线程综合裁决。
  触发方式：/story-review、/审查、「审查一下」「帮我审一下」
metadata:
  openclaw:
    source: https://github.com/worldwonderer/oh-story-claudecode
---

# story-review：多视角对抗式审查

你是审查协调器。并行 spawn 4 个 Agent，各自从不同角度找问题，然后综合裁决。

**执行铁律：审查是找问题，不是验证正确性。**

---

## Review Mode 选择

- `/story-review` 或 `/story-review full` → spawn 全部 4 个 Agent（仅主会话使用；如果当前已经在子代理内，自动降级为 solo）
- `/story-review lean` → 只 spawn story-architect + consistency-checker（仅主会话使用；子代理内自动降级为 solo）
- `/story-review solo` → 不 spawn Agent，自身做基础检查
- 未指定 → 默认 full，并告知用户

---

## 审查流程（full 模式）

## 参考文件路径规则（必须遵守）

story-review 会把参考资料交给子 Agent。**所有传给 Agent 的参考文件必须使用本 skill 内的规范路径，禁止只写裸文件名，也禁止跨 skill 引用其他 skill 的 references。**

路径解析顺序：
1. `{项目根}/.claude/skills/{规范路径}`（Claude Code / OpenClaw 项目内安装）
2. `{项目根}/skills/{规范路径}`（本仓库开发环境）
3. 工具自身的全局 skill 搜索路径中同名 `{skill-name}/...` 目录

传给 Agent 时使用如下规范路径，并明确要求 Agent 不要读取裸文件名：

| 用途 | 规范路径 |
|---|---|
| 通用质量清单 | `story-review/references/quality-checklist.md` |
| 去 AI 味方法 | `story-review/references/anti-ai-writing.md` |
| 剧情循环/高潮公式 | `story-review/references/plot-core-methods.md` |
| 角色关系/好感度 | `story-review/references/character-relations.md` |
| 对话质量 | `story-review/references/dialogue-mastery.md` |
| 审查禁用词 | `story-review/references/banned-words.md` |
| 默认 rubric | `story-review/references/quality-rubric.md` |
| 平台 rubric | `story-review/references/rubrics/{fanqie,qidian,zhihu}.md` |

如果某工具只接受当前目录相对路径，先尝试 `.claude/skills/story-review/references/{file}` 和 `skills/story-review/references/{file}`；找不到再用 Glob/Grep 搜索 `*/story-review/references/{file}`；禁止改读其他 skill 的 references。

## Phase 1：收集待审查内容

1. 确定审查范围：
   - 用户指定了章节/文件 → 只审查指定内容
   - 用户未指定 → 审查最近修改的内容（git diff）或当前章节
2. 读取待审查的正文内容
3. 读取相关的设定文件和大纲
4. 识别目标平台（检查 `.active-book` 或用户指定），加载对应 rubric：
   - 番茄小说 → 读取 `story-review/references/rubrics/fanqie.md`（优先 `.claude/skills/story-review/...`，其次 `skills/story-review/...`）
   - 起点 → 读取 `story-review/references/rubrics/qidian.md`（优先 `.claude/skills/story-review/...`，其次 `skills/story-review/...`）
   - 知乎盐言 → 读取 `story-review/references/rubrics/zhihu.md`（优先 `.claude/skills/story-review/...`，其次 `skills/story-review/...`）
   - 未指定 → 默认加载 `story-review/references/quality-rubric.md`（优先 `.claude/skills/story-review/...`，其次 `skills/story-review/...`）

**Phase 1.5：可选 story-explorer 预查询**。如果项目已部署 story-explorer agent（检查 `.claude/agents/story-explorer.md` 是否存在），可 spawn `Agent(subagent_type: "story-explorer", prompt: "项目目录：{dir}\n查询类型：setting_appearances\n查询参数：{审查涉及的设定关键词}")` 预查设定摘要，将结果注入各 agent 的 prompt，减少重复 grep。此步可选，跳过不影响审查流程。

## Phase 2：双 Pass 评审架构（v1.1.0 — issue #88 内容安全规避）

> **架构变更（v0.8.0）**：旧的「一次性把 卷纲 + 多章正文塞进 4 个 Agent」做法会触发 Anthropic 内容安全（issue #88）。新架构拆分为 **Phase 2A 单章并行（local）** + **Phase 2B 摘要驱动（global）**，配合 **CHAPTER_META 中间产物**做算术聚合。详见 `skills/story-review/UPGRADING.md`。

> **CHAPTER_META 契约**：Phase 2A 每个 Agent 在自然语言 FINDINGS 之外，必须输出符合 `skills/story-review/references/chapter-meta-schema.json` 的 JSON 块（schema_version `1.0`）。Phase 2B 主协调器对这些 JSON 做纯算术聚合（不再 spawn 额外 LLM 看正文）。

> **解耦**：consistency-checker **不参与 Phase 2A**（它是 grep-first / 跨章 by 性质）。Phase 2A 只 spawn 3 个创作型 Agent（story-architect / character-designer / narrative-writer），按章节并行。consistency-checker 在 Phase 2B 跑一次（全局）。

### Phase 2A：Local Pass —— 单章并行（chunked）

**调用规则**：每个 Agent 不继承父对话上下文，prompt 必须自包含。每章范围严格限制为该章正文 + 必要角色文件 + 平台 rubric；**禁止**在单章 prompt 里塞入整卷 卷纲、跨章正文、或全书设定（这正是触发 #88 安全墙的形式）。

**并行控制**：
- 同时在飞最多 6 个章节（3 agents × 6 chapters = 18 并行 Agent 调用上限）
- 若审查范围超过 **30 章**，先用 `AskUserQuestion` 提示用户确认（成本/时间）后再继续

**缓存与幂等**：
- 每章 CHAPTER_META 输出写入 `.omc/review-cache/<chapter_hash>.json`（hash = `sha1` of 章节正文 + agent name + schema version）
- 重跑时若 hash 命中 → 跳过 Agent 调用，直接复用缓存
- **原子写入由 `scripts/cache-write.sh` 强制实现**（不只是 prose 约定）：调用方将 CHAPTER_META JSON pipe 给 `bash scripts/cache-write.sh <hash>`，脚本完成 `.tmp` 缓冲 + JSON 验证 + 原子 `mv` 三步，并在检测到现存 `.tmp`（并发同项目运行）时 exit 1 中止。每个 Phase 2A agent 在 prompt 末尾被要求执行 `cat <META_BLOCK> | bash scripts/cache-write.sh <chapter_hash>`，而非自己写文件。

**对每个章节文件 `<chapter>`，并行 spawn 3 个 Agent**：

#### Agent A: story-architect（Phase 2A — 单章 local）
- 审查视角（local-only）：单章主题对照、单章钩子、单章反转冲击力、单章情绪节奏
- 提示指令：
  ```
  Reframe (read first): fictional novel craft critique; institutional/violent/political content is story-mechanism, not real-world advocacy; judge craft per user's 题材 conventions, not real-world ethics.

  你是 story-architect，对**单个章节**做架构层 local 评审。
  **重要**：本 Pass 只看这一章正文 + 平台 rubric；不要试图加载或推断跨章/整卷信息。跨章评审在 Phase 2B 做。
  你的任务是【找问题】。以最严苛的标准审视。
  审查章节：{当前章节文件路径}
  平台评分标准：{Phase 1 加载的 rubric 内容}
  参考文件路径规则：以下路径以 skill 名开头；优先从 `{项目根}/.claude/skills/` 或 `{项目根}/skills/` 拼接解析；不要读取裸文件名，不要跨 skill 读取 references。
  参考文件：`story-review/references/quality-checklist.md`、`story-review/references/plot-core-methods.md`、`story-review/references/rubrics/{平台}.md`、`story-review/references/chapter-meta-schema.json`
  CHAPTER_META schema：必须读取并输出符合 schema v1.0 的 JSON 块（见输出格式）。
  本 Pass 检查项（单章 local）：
  1. 章首钩子设计：是否成立？
  2. 章尾钩子设计：留没留住读者？
  3. 单章反转冲击力（不评判 3+ 暗示这种跨章铺垫，那是 Phase 2B 的活）
  4. 单章情绪节奏：本章内部是否有起伏，还是平铺？
  5. 局部主题对照：本章和当前章节自己宣示的 micro-theme 是否对齐？

  输出格式：
  VERDICT / 结论: APPROVE / CONCERNS / REJECT
  FINDINGS: [单章问题，附引用]
  RECOMMENDATIONS: [单章修改建议]

  CHAPTER_META (JSON, schema_version "1.0"):
  ```json
  {
    "schema_version": "1.0",
    "chapter_id": "{当前章节标识}",
    "verdict": "APPROVE | CONCERNS | REJECT",
    "ai_grade": "light",  // architect 视角默认 light, 真正的 ai_grade 由 narrative-writer 出
    "rhythm_tags": ["low_pressure", "high_pressure", ...],
    "emotional_beats": [
      {"position_pct": 10, "emotion_type": "tension"},
      {"position_pct": 80, "emotion_type": "release"}
    ],
    "s2_count": <int>, "s3_count": <int>, "s4_count": <int>
  }
  ```
  ```

#### Agent B: character-designer（Phase 2A — 单章 local）
- 审查视角（local-only）：单场景动机/潜台词/对话差异化/单章好感度行为
- 提示指令：
  ```
  Reframe (read first): fictional novel craft critique; characters' moral failings/coercion/violence are character-arc elements, not real-world advocacy; judge character agency per user's 题材 conventions, not real-world ethics.

  你是 character-designer，对**单个章节**做角色层 local 评审。
  **重要**：本 Pass 只看这一章 + 该章涉及角色的角色档案；不要做跨章弧线/好感度趋势判断（那是 Phase 2B 的活）。
  你的任务是【找问题】。
  审查章节：{当前章节文件路径}
  相关角色文件：{该章出场角色的设定文件路径，从单章 grep 角色名得出}
  参考文件路径规则：同上。
  参考文件：`story-review/references/character-relations.md`、`story-review/references/dialogue-mastery.md`、`story-review/references/chapter-meta-schema.json`
  本 Pass 检查项（单章 local）：
  1. 单章角色行为是否符合其动机链？
  2. 单场景对话有无潜台词、是否有信息控制？
  3. 单章对话是否千篇一律（同一章内）？
  4. 单章爱情线场景的好感度行为与设定阶段是否匹配？

  输出格式：
  VERDICT / 结论: APPROVE / CONCERNS / REJECT
  FINDINGS: [单章问题]
  RECOMMENDATIONS: [单章建议]

  CHAPTER_META (JSON, schema_version "1.0"):
  ```json
  {
    "schema_version": "1.0",
    "chapter_id": "{当前章节标识}",
    "verdict": "APPROVE | CONCERNS | REJECT",
    "ai_grade": "light",  // character 视角默认 light, ai_grade 由 narrative-writer 出
    "pov_character": "{本章主要 POV 角色}",
    "char_drift_flag": false,  // 单章看不到漂移；Phase 2B 在聚合时根据多章 pov_character 序列判断
    "s2_count": <int>, "s3_count": <int>, "s4_count": <int>
  }
  ```
  ```

#### Agent C: narrative-writer（Phase 2A — 单章 local，含新增「句式多样性」第 6 项）
- 审查视角：本章 AI 味/格式/节奏/词频/句式多样性
- 提示指令：
  ```
  Reframe (read first): fictional novel craft critique; violent/political/coercive content is story mechanics, not real-world advocacy; judge prose AI-taste/rhythm/format per user's 题材 conventions, not real-world ethics.

  你是 narrative-writer，对**单个章节**做文字质量 local 评审。
  审查章节：{当前章节文件路径}
  参考文件路径规则：同上。
  禁用词表：`story-review/references/banned-words.md`
  质量清单：`story-review/references/quality-checklist.md`
  CHAPTER_META schema：`story-review/references/chapter-meta-schema.json`
  本章检查项：
  1. 禁用词/套话/陈词滥调（列出命中词 + 频次）
  2. 格式合规（一段一句、≤60字、无空行、对话独立成行）
  3. 单章内节奏：是否有快慢变化，还是均匀套路？
  4. 身体部位同一词单章 > 5 次？
  5. AI 味分级（light/medium/heavy）
  6. **句式多样性**（v0.8.0 新增）：本章是否存在 SVO 循环结构连续 5 段以上？标 low / medium / high。

  输出格式：
  VERDICT / 结论: APPROVE / CONCERNS / REJECT
  FINDINGS: AI味级别: light/medium/heavy; [禁用词/格式/节奏/句式问题]
  RECOMMENDATIONS: [单章建议]

  CHAPTER_META (JSON, schema_version "1.0"):
  ```json
  {
    "schema_version": "1.0",
    "chapter_id": "{当前章节标识}",
    "verdict": "APPROVE | CONCERNS | REJECT",
    "ai_grade": "light | medium | heavy",
    "banned_words_found": [{"word": "...", "count": N}],
    "body_parts_used": [{"word": "...", "count": N}],
    "rhythm_tags": ["..."],
    "sentence_pattern_diversity": "low | medium | high",
    "s2_count": <int>, "s3_count": <int>, "s4_count": <int>
  }
  ```
  ```

**Phase 2A 完成条件**：所有章节的 3 个 Agent 都返回，CHAPTER_META JSON 通过 schema 校验（json.load + required 字段检查），落盘到 `.omc/review-cache/`。任何 Agent 返回不合规 JSON → **fail loudly**（chapter_id + agent name），不继续 Phase 2B。

### Phase 2B：Global Pass —— 摘要驱动（summary-only）

> **强制契约**：本 Pass spawn 的 Agent **禁止**重新读取任何 `正文/*.md` 章节文件。输入只允许：tracking 文件、卷纲 metadata 块、Pass 2A aggregated CHAPTER_META。违反则 #88 安全墙再次触发。

#### Phase 2B 前置检查 —— 追踪文件 freshness

主协调器先验证以下文件存在且不过期：

| 文件 | 必需 | 失效判定 |
|---|---|---|
| `{书}/追踪/角色状态.md` | 是 | 文件缺失，或 mtime 早于 `{书}/正文/` 中最新章节 mtime > 7 天 |
| `{书}/追踪/伏笔.md` | 是 | 同上 |
| `{书}/追踪/时间线.md` | 否（可降级） | 缺失 → 时间线检查 SKIPPED |
| `{书}/大纲/卷纲_*.md` 或 `{书}/大纲/大纲.md` | 是 | 缺失或无结构化 section（无 `## 主题`/`## 卖点`/`## 事件清单` 任一段） |

**失效响应**：对每个失效项，输出 `SKIPPED: <check 名称> (reason: 缺 <file> / 过期 / 无结构化 section)`，并提示用户：
- 缺失 → `bash scripts/bootstrap-tracking.sh --book <书名>` 反推追踪文件
- 过期 → 手动更新或重跑 `/story-long-write 续写` 时自动更新追踪
- 无结构化 section → 在 卷纲 中加入 `## 主题`、`## 卖点`、`## 事件清单` 三个 H2 段

**绝对不要**在 SKIPPED 项上输出 PASS/FAIL。

#### Phase 2B 大纲 metadata 提取

主协调器从 卷纲/大纲 中**只提取**以下三类结构化 section：
- `## 主题`（或 `## 核心主题`）
- `## 卖点`（或 `## 题材定位` / `## 核心梗`）
- `## 事件清单`（或 `## 章节清单` / `## 卷纲事件`）

把提取出的纯结构化文本作为 Phase 2B Agent 输入的 `卷纲_summary` 字段。**不传**卷纲全文。

#### Phase 2B Agent 调用

并行 spawn 3 个 Agent：

##### Agent D: consistency-checker（Phase 2B）
- 视角：跨章事实冲突（5 项原有检查）
- 输入：`追踪/角色状态.md`、`追踪/伏笔.md`、`追踪/时间线.md`（如有）、设定文件、卷纲 metadata、Pass 2A aggregated CHAPTER_META
- prompt 增加约束：
  ```
  你是 consistency-checker。本次为 global pass，使用 grep-first + 摘要驱动。
  **禁止**重新加载 正文/ 章节文件做整体读取；可以 grep 单点关键词，但不要 Read 整章。
  审查范围：跨章一致性
  已知角色：{从 角色状态.md 提取}
  跨章 CHAPTER_META（聚合）：{Pass 2A 聚合产物，见 scripts/aggregate-review.sh 输出}
  参考文件路径规则：同 Phase 2A。
  质量清单：`story-review/references/quality-checklist.md`
  检查项（5 项原有）：角色属性 / 世界规则 / 伏笔埋设回收 / 时间线 / 伏笔密度
  输出格式：
  VERDICT / 结论: APPROVE / CONCERNS / REJECT
  FINDINGS: [S1/S2/S3/S4] 冲突描述（每条标置信度 HIGH / MEDIUM / LOW；详见置信度定义）
  RECOMMENDATIONS: [修复建议]
  ```

##### Agent E: story-architect（Phase 2B —— 跨章 only）
- 视角：跨章结构（范围控制 / 剧情循环 / 卖点偏移 / 连载连续性 / 伏笔推进 / 主题对照全局）
- 输入：卷纲 metadata、追踪文件、Pass 2A aggregated CHAPTER_META（含 emotional_beats 序列）
- prompt 同 Phase 2A architect 的 reframe，但检查项替换为跨章 only：
  ```
  Reframe (read first): 同 Phase 2A architect.

  你是 story-architect，做**跨章 global** 评审。
  **禁止**重新加载 正文/ 章节文件；输入只有 卷纲 metadata + 追踪 + CHAPTER_META 聚合。
  审查输入：
  - 卷纲 metadata：{主题 / 卖点 / 事件清单 提取后的纯文本}
  - 追踪/角色状态.md、追踪/伏笔.md
  - Pass 2A CHAPTER_META 聚合：{含 emotional_beats 序列、rhythm_tags 分布、伏笔 lifecycle}
  参考文件路径规则：同 Phase 2A。
  参考文件：`story-review/references/quality-checklist.md`、`story-review/references/plot-core-methods.md`
  本 Pass 检查项（跨章 only）：
  1. 范围控制：角色/设定膨胀（对照 角色状态.md 出场度）
  2. 剧情循环是否存在且可重复（看事件清单结构）
  3. 卖点偏移：实际 emotional_beats 序列与 卖点 是否同频？
  4. 连载连续性：伏笔是否在推进（planted vs resolved）？
  5. 主题对照全局：所有章节的 micro-theme 加起来，是否服务于卷主题？

  每条 FINDING 必须带置信度标签（HIGH / MEDIUM / LOW）。

  输出格式：
  VERDICT / 结论: APPROVE / CONCERNS / REJECT
  FINDINGS: [跨章问题；每条带 [HIGH] / [MEDIUM] / [LOW]]
  RECOMMENDATIONS: [跨章建议]
  ```

##### Agent F: character-designer（Phase 2B —— 跨章 only）
- 视角：跨章弧线（人物弧线连贯 / 好感度趋势 / 语言风格漂移）
- 输入：追踪/角色状态.md、追踪/关系.md（如有）、Pass 2A aggregated CHAPTER_META（pov_character 序列）
- prompt：
  ```
  Reframe (read first): 同 Phase 2A character-designer.

  你是 character-designer，做**跨章 global** 评审。
  **禁止**重新加载 正文/ 章节文件；输入只有 追踪 文件 + CHAPTER_META 聚合。
  审查输入：
  - 追踪/角色状态.md、追踪/关系.md（如有）、设定/角色/*.md
  - Pass 2A CHAPTER_META 聚合：{pov_character 序列、char_drift_flag 章节列表}
  参考文件路径规则：同 Phase 2A。
  参考文件：`story-review/references/character-relations.md`、`story-review/references/dialogue-mastery.md`
  本 Pass 检查项（跨章 only）：
  1. 人物弧线连贯：成长触发 / 变化铺垫 / 转折点是否在 角色状态.md 时间戳里清晰？
  2. 好感度趋势：跨章 milestone 是否可感知（看 角色状态.md「最近一次变化」「最新状态」字段对照）？
  3. 语言风格跨章漂移：char_drift_flag 标记的章节是否对应有意的弧线（角色档案有「预期语言风格弧线」字段则对齐）还是无意漂移？

  每条 FINDING 必须带置信度标签。

  输出格式：
  VERDICT / 结论: APPROVE / CONCERNS / REJECT
  FINDINGS: [跨章角色/语言风格问题；每条带置信度]
  RECOMMENDATIONS: [跨章建议]
  ```

> **诚实标注**：character-designer 在 Phase 2B 无法判定「情感可感知度」（读者主观温度）—— 摘要文件只能体现状态变化，不能体现场景情感密度。**此项不在本 Pass 检查范围**；若用户关心，需 manually re-read 关键章节正文。

#### 置信度标签 operational 定义

| 标签 | 触发条件 |
|---|---|
| **HIGH** | finding 来自 tracking 文件直接陈述（如 角色状态.md 明确说「主角实力第三层」，而正文 grep 出「第五层」） |
| **MEDIUM** | finding 来自 CHAPTER_META 聚合（如禁用词在 8/12 章出现） |
| **LOW** | finding 来自 卷纲 metadata 推断（如 卷纲 写「高潮章」但 CHAPTER_META 中那些章 rhythm_tags 没有 climax） |

报告中每条 Pass 2B 的 finding 必须显式标注。

#### Pass 2 完成后：算术聚合（见 S-004）

主协调器调用 `bash scripts/aggregate-review.sh` 对 `.omc/review-cache/*.json` 做统计聚合。聚合输出作为 Phase 4 报告的「Cumulative Patterns」section 直接嵌入。

## Phase 3：综合裁决

1. 收集 Phase 2A（每章 3 个 Agent）+ Phase 2B（3 个 Agent）的 VERDICT 和 FINDINGS
2. 调用 `bash scripts/aggregate-review.sh` 对 `.omc/review-cache/*.json` 做算术聚合，生成「Cumulative Patterns」section
3. 合并去重：FINDINGS 按 (S1 > S2 > S3 > S4) + (AI 味重度 > 中度 > 轻度) 排序；Phase 2B FINDINGS 显式标注置信度（HIGH/MEDIUM/LOW）
4. **可选事实核查**：如果审查内容涉及需要验证的外部事实，额外 spawn `story-researcher` agent
5. **分歧呈现**：Agent 间冲突意见明确呈现，不自动妥协
6. **SKIPPED 项透传**：Phase 2B 因追踪/大纲文件失效而 SKIPPED 的检查必须出现在报告里（不能默默忽略），并给出修复指引

## Phase 4：输出报告（full 模式）

```
=== 故事审查报告 (v1.1.0 双 Pass 架构) ===
Review Mode: full
审查范围: {章节列表 / 文件}
追踪文件健康: ✓ / ✗ (列出 SKIPPED 项)

## Phase 2A Local Pass 汇总（每章 verdict）
| 章节 | story-architect | character-designer | narrative-writer (ai_grade) |
|------|-----------------|--------------------|-----------------------------|
| 第N章 | APPROVE | CONCERNS(2) | medium |
...

## Phase 2B Global Pass 汇总
- consistency-checker: APPROVE / CONCERNS(n) / REJECT
- story-architect (跨章): APPROVE / CONCERNS(n) / REJECT
- character-designer (跨章): APPROVE / CONCERNS(n) / REJECT

## Cumulative Patterns（来自 scripts/aggregate-review.sh）
{aggregate 输出嵌入：禁用词跨章 reuse、AI-grade 分布、rhythm 方差、伏笔 lifecycle 等}

## 综合评定
{APPROVE / CONCERNS / REJECT}

## SKIPPED 项（Phase 2B 失效检查）
{列出每个 SKIPPED + 修复指引；若全跑则此段为空}

## 发现的问题
{按 S1→S4 分级列出所有问题}

## Agent 分歧（如有）
{列出 Agent 间不同的意见}

## 修改建议
{按优先级排列}
```

---

## lean 模式

只 spawn story-architect + consistency-checker，跳过 character-designer 和 narrative-writer。
其余流程同 full。

### lean 模式输出格式

```
=== 故事审查报告（lean）===
Review Mode: lean
审查范围: {章节/文件}

## Verdict Summary / 结论汇总
- story-architect: APPROVE / CONCERNS(n) / REJECT
- consistency-checker: APPROVE / CONCERNS(n) / REJECT

## 综合评定
{APPROVE(通过) / CONCERNS(有问题) / REJECT(需重写)}

## 发现的问题
{按 S1→S4 分级}

## 修改建议
{按优先级排列}
```

## solo 模式

不 spawn Agent。先按 Phase 1 第 4 步识别目标平台并加载对应 rubric；即使是 solo，也必须用平台 rubric 校准判断。skill 自身执行基础检查：
1. 格式合规性检查（一段一句、无空行、对话格式）
2. 简单的设定一致性 grep
3. 输出简化版报告

### solo 模式输出格式

```
=== 故事审查报告（solo）===
Review Mode: solo
审查范围: {章节/文件}

## 基础检查结果

### 格式合规性
- [ ] 段落 ≤60 字
- [ ] 无段间空行
- [ ] 对话独立成行
- 违规位置：{列出}

### 设定一致性（grep 扫描）
- {列出发现的矛盾}

### 简评
{一段话总结}
```

---

## 语言

- 跟随用户的语言回复，用户用什么语言就用什么语言回复
- 中文回复遵循《中文文案排版指北》
