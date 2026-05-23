# 升级指南

## 升级策略

| 策略 | 适用场景 | 风险 |
|------|----------|------|
| 覆盖部署 | 全新项目或无需保留自定义 | 低 |
| 合并部署 | 有自定义内容需保留 | 中 |
| 手动更新 | 只改特定文件 | 低 |

推荐：运行 `/story-setup` 重新部署，自动走合并策略。

## 文件分类

### 可安全覆盖

这些文件由 story-setup 管理，不含用户自定义内容：
- `.claude/hooks/` — 所有 hook 脚本
- `.claude/agents/` — 所有 agent 定义
- `.claude/rules/` — 所有 path-scoped 规则

### 需合并（不覆盖）

这些文件可能含用户自定义内容：
- `CLAUDE.md` — 按 section 合并，用户独有 section 保留
- `.claude/settings.local.json` — hooks 按 command 去重 append，其他配置保留

### 不碰

这些文件完全由用户管理：
- `{书名}/追踪/上下文.md` — 用户写作上下文
- `{书名}/追踪/伏笔.md` — 用户伏笔追踪
- `.active-book` — 用户活跃书目

## 版本检测

`.story-deployed` 文件记录部署版本：
- 无此文件 → 未部署，需全新安装
- `agents_version: 1` → 旧版，需重新部署以获取新 Agent
- `agents_version: 2` → 旧版，需重新部署以获取 story-explorer agent
- `agents_version: 3` → 旧版，需重新部署以获取 story-explorer agent
- `agents_version: 4` → 旧版，需重新部署以获取 chapter-extractor agent
- `agents_version: 5` → 旧版，需重新部署以统一短篇主会话/子代理正文格式
- `agents_version: 6` → 旧版，需重新部署以获取日更续写与伏笔 hook 修复
- `agents_version: 7` → 旧版，需重新部署以获取 Agent 参考文件路径修复
- `agents_version: 8` → 旧版，需重新部署以迁移到 `<<STORY_REF>>` 占位符 + 部署时 sed 渲染
- `agents_version: 9` → 当前版本

## 版本变更

### v2

- 4 个创作型 Agent + 1 个研究型 Agent（story-architect, character-designer, narrative-writer, consistency-checker, story-researcher）
- Agent 引用 skill references 写作理论
- Hook 脚本优化（减少 context 输出）
- 4 条 path-scoped 规则

### v3

- 新增 story-explorer 只读查询 Agent（角色/伏笔/设定/进度查询，日更上下文快速加载）
- 6 个 Agent 总计（story-architect, character-designer, narrative-writer, consistency-checker, story-researcher, story-explorer）
- story-explorer 被 story-long-write、story-review、story 路由集成调用

### v4

- 新增 chapter-extractor 章节提取 Agent
- 7 个 Agent 总计（story-architect, character-designer, narrative-writer, consistency-checker, story-researcher, story-explorer, chapter-extractor）

### v5

- 更新 narrative-writer 场景写法：使用“三维度织入”并按镜头断段控制段落密度
- 字数统计改为 Python 字符统计优先，`wc -m` 仅作 macOS/Linux 备选，提升 Windows + DeepSeek/Claude Code 兼容性
- 已部署项目重新运行 `/story-setup` 后获取新版 agent 定义

### v6

- 统一 narrative-writer 子代理与主会话的短篇正文格式：固定写入 `正文.md`、小节标记统一、段落无空行、对话半角双引号
- 短篇写作不再由 narrative-writer 创建长篇 `追踪/上下文.md`

### v7

- 修复长篇 `/story-long-write 日更` 批量续写中的 continuation 规则：同一批次内“继续/续写/日更”保持在 daily workflow，不直接跳到正文续写。
- 修复 `detect-story-gaps.sh` 对伏笔表头和正常开放伏笔（`未埋`/`已埋`）的误报；SessionStart 只提示 `已过期` 或异常状态。
- 已部署项目需重新运行 `/story-setup`，以覆盖 `.claude/hooks/`、`.claude/agents/`、`.claude/rules/` 并获得新版 hook 行为。

### v8

- 修复 story-review 及部署后的 reviewer Agent 在项目根目录下读取参考文件时，只找裸文件名（如 `quality-checklist.md`）导致找不到 skill references 的问题。
- Agent 模板新增参考文件路径规则：优先从 `.claude/skills/` 或 `skills/` 拼接解析 `story-setup/references/agent-references/*.md` 规范路径，避免依赖当前工作目录且不跨 skill 引用 references。
- 已部署项目需重新运行 `/story-setup`，以覆盖 `.claude/agents/` 并获得新版参考文件路径规则。

### v9 (当前)

**Breaking change：v8 用户必须重跑 `/story-setup`，否则 agent 读不到 references。**

- 路径迁移到模板占位符 + 部署时 resolve：creative agent（story-architect / character-designer / narrative-writer / consistency-checker）模板内所有 `story-setup/references/agent-references/X.md` 路径替换为 `<<STORY_REF>>/X.md`。`/story-setup` 部署时 `sed` 把占位符渲染成 `.claude/agent-references/X.md` 的相对路径。
- 部署新增 Phase 2.4.2 步骤：把 21 个 references `.md` 复制到项目根目录 `.claude/agent-references/`，然后对 `.claude/agents/` 下所有文件执行 `sed -i.bak 's|<<STORY_REF>>|.claude/agent-references|g'`。
- Phase 3 新增校验：`grep -rln '<<[A-Z_]+>>' .claude/agents/` 必须输出 0 行；如有残留说明 sed 替换失败。
- agent 模板内删除三段式 fallback prose（`.claude/skills/` → `skills/` → Glob 搜索），替换为单段 advisory：若运行时仍能读到裸 `<<STORY_REF>>`，说明用户没跑过 setup，提示运行 `bash scripts/dev-setup.sh` 或 `/story-setup`，不要再尝试 fallback 搜索。
- sentinel `.story-deployed` 新增字段：`target_cli: claude-code`、`resolver_strategy: template-placeholder`、`references_dir: .claude/agent-references`；`agents_version` bump 到 `9`。
- S1 修复：`detect-story-gaps.sh` 改用数组长度检查兼容 macOS bash 3.2，删除短篇 if/else dead code；`story-format.md` 移除「章节之间用 `---` 分隔」与 narrative-writer 「禁止水平分隔线」的规则矛盾。
- 新增贡献者脚本：`scripts/dev-setup.sh`（worktree 内一键渲染 21 refs + 7 agents）+ `scripts/install-hooks.sh`（设置 `core.hooksPath`）。

OpenClaw / 其他非 claude-code CLI 的兼容性 spike 推迟到 v10；当前 v9 默认 `target_cli=claude-code`，details 见 `.omc/notes/openclaw-spike.md`。
