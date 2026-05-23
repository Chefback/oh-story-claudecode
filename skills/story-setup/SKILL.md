---
name: story-setup
version: 1.1.0
description: |
  网文写作工具集基础设施部署。将 hooks/rules/agents/CLAUDE.md 等基础设施部署到用户项目目录。
  触发方式：/story-setup、「准备写书」「帮我搭一下环境」「配置写作项目」
metadata:
  openclaw:
    source: https://github.com/worldwonderer/oh-story-claudecode
---

# story-setup：网文写作工具集基础设施部署

你是写作基础设施部署器。将网文写作工具集的全套基础设施（hooks、rules、agents、CLAUDE.md）部署到用户项目目录。

**执行铁律：不覆盖用户已有配置，合并而非替换。**

---

## Phase 1：检测项目状态

1. 检查当前目录是否已部署过（存在 `.story-deployed`）
   - 如果已存在 → 使用 AskUserQuestion 确认是否重新部署
2. 检查是否有书名目录（包含 `追踪/` 子目录的目录，或用户自定义结构）
   - 有 → 识别为长篇项目，显示当前项目信息
   - 无 → 识别为新项目或短篇项目
3. 检查 `.claude/settings.local.json` 是否存在
   - 存在 → 读取现有配置，后续合并
   - 不存在 → 后续创建新文件
4. 检查 `.active-book` 文件是否存在
   - 存在 → 显示当前活跃书目
   - 不存在 → 跳过

## Phase 2：部署基础设施

使用 AskUserQuestion 确认部署位置后，依次执行：

### 2.1 部署 CLAUDE.md
- 读取 `skills/story-setup/references/templates/CLAUDE.md.tmpl`
- 替换占位符（见下方「模板占位符」段）
- 写入项目根目录 `CLAUDE.md`（如已存在，按「CLAUDE.md 合并策略」处理）

### 2.2 部署 Hooks
- 复制 `skills/story-setup/references/templates/hooks/` 下所有 `.sh` 文件到 `.claude/hooks/`
- 同时复制子目录 `lib/`（含 `common.sh` 提供 `discover_active_book`/`discover_all_books`，`sentinel.sh` 提供 `read_sentinel_field`），目标 `.claude/hooks/lib/`
- 确保 `.claude/hooks/*.sh` 有执行权限（chmod +x）；`lib/*.sh` 是 source 进来的，不需要可执行位

### 2.3 部署 Rules
- 读取 `skills/story-setup/references/templates/rules/` 下所有 `.md` 文件
- 复制到用户项目的 `.claude/rules/` 目录

### 2.4 部署 Agents
- 读取 `skills/story-setup/references/templates/agents/` 下所有 `.md` 文件
- 复制到用户项目的 `.claude/agents/` 目录
- Agent 文件属于 story-setup 管理文件，可安全覆盖；版本升级时按 `UPGRADING.md` 的版本检测结果重新部署

### 2.4.1 Agent 兼容性处理
- Agent frontmatter 以 Claude Code 为主；OpenClaw/qclaw 等只要支持 AgentSkills，未知字段（如 `memory`、`skills`、`disallowedTools`）应被忽略。若目标工具报 frontmatter 错误，保留 `name`、`description`、`tools` 三项，删除不支持字段后再部署。

### 2.4.2 部署 Agent References

agent 模板内的参考资料路径都以 `<<STORY_REF>>` 占位符表示。部署时必须把 references 复制到工作区并解析占位符，运行时只走这一条路径，不依赖跨 skill 查找。

1. 复制参考资料：把 `skills/story-setup/references/agent-references/` 下所有 `.md`（21 个，不含 `_attic/`）复制到项目根目录 `.claude/agent-references/`
2. 解析占位符：对 `.claude/agents/` 下每个已部署 agent 文件执行 `sed -i.bak 's|<<STORY_REF>>|.claude/agent-references|g'` 替换占位符为相对路径
   - 替换后删除 `.bak` 备份文件
   - 注意：macOS 的 `sed -i` 需要 `-i.bak` 形式（GNU sed 用 `-i ''`，部署脚本里写 `sed -i.bak ... && rm -f *.bak`）
3. 校验：`grep -rln '<<[A-Z_]+>>' .claude/agents/` 必须输出 0 行；如有残留占位符说明替换失败，需排查后重跑

> 贡献者本地（worktree 模式）跑 `bash scripts/dev-setup.sh` 等价完成 2.4 + 2.4.2，无需走 `/story-setup`。

### 2.5 部署 Session State 模板
- 读取 `skills/story-setup/references/templates/上下文.md.tmpl`
- 如有书名目录，复制到 `{书名}/追踪/` 下

### 2.6 合并 Hooks 注册到 settings.local.json

> 兼容性说明：`settings-hooks.json` 中 PreToolUse 的 `if` 字段使用 Claude Code hook 条件语法，需要运行环境支持 hook-level if。若目标工具不支持该字段，hook 脚本本身仍会自检并 advisory-only 退出；部署时可删除该 `if` 字段并保留 matcher + command。

- 读取 `skills/story-setup/references/templates/settings-hooks.json`
- 读取用户项目的 `.claude/settings.local.json`（如存在）
- 合并 hooks 配置（按「settings-hooks.json 合并算法」处理）
- 写入 `.claude/settings.local.json`

### 2.7 创建部署标记

- 创建 `.story-deployed` 文件（sentinel file）
- 写入以下字段（YAML key: value 格式，hook 用 grep+sed 读取，详见 `references/templates/hooks/lib/sentinel.sh`）：
  ```
  deployed_at: <date -u +"%Y-%m-%dT%H:%M:%SZ">
  agents_version: 9
  setup_skill_version: 1.1.0
  target_cli: claude-code
  resolver_strategy: template-placeholder
  references_dir: .claude/agent-references
  ```
- 此文件供 session-start.sh 和写作 skill 检测部署状态，避免重复提示
- 如果 `.story-deployed` 已存在但无 `agents_version` 或版本 < 9，提示用户重新运行 story-setup 以更新 hooks/agents/rules。每次 bump 的具体变更见 `UPGRADING.md`。

## Phase 3：验证安装

1. 验证 hooks 注册：
   - 检查 `.claude/settings.local.json` 中的 hooks 字段是否正确
   - 检查 `.claude/hooks/` 下的脚本是否存在且有执行权限
2. 验证 rules 路径：
   - 检查 `.claude/rules/` 下的规则文件是否存在且包含 `paths` frontmatter
3. 验证 agents：
   - 检查 `.claude/agents/` 下的 agent 定义文件是否存在
4. 验证 agent-references 与占位符替换：
   - 检查 `.claude/agent-references/` 下 `.md` 数量 ≥ 21
   - 执行 `grep -rln '<<[A-Z_]+>>' .claude/agents/`，必须输出 0 行；如有残留说明 `sed` 替换失败
5. 验证部署标记：
   - 检查 `.story-deployed` 是否存在且包含时间戳、`agents_version: 9`、`target_cli`、`resolver_strategy`、`references_dir`
6. 输出安装报告：
   - 列出所有已部署的文件
   - 列出需要注意的事项（如已有配置已合并）
   - 提示用户可以开始使用 `/story-long-write` 或 `/story-short-write`

---

## 模板占位符

| 占位符 | 替换规则 | 示例 |
|--------|----------|------|
| `{项目名}` | 用户项目名称或目录名 | 《剑来》、《暗卫》 |
| `{书名}` | 书名目录名（与目录一致） | 与 `{项目名}` 相同，或用户自定义 |
| `{目标平台}` | 目标发布平台 | 起点、番茄、晋江、知乎盐言 |
| `{作者名}` | 用户笔名或昵称 | 未指定时用「作者」 |

替换时去掉花括号。如果用户未指定项目名，用当前目录名。未指定的占位符保留原样不替换。

## CLAUDE.md 合并策略

用户已有 CLAUDE.md 时，按 section 合并：
1. 读取用户现有 CLAUDE.md，按 `##` 标题切分为 section map
2. 读取模板 CLAUDE.md.tmpl，同样切分
3. 模板中的标准 section（Skill 路由表、文件结构、协作规则、Context Recovery、语言）**覆盖**用户同名 section
4. 用户独有的 section（自定义内容）**保留**不动
5. 未知冲突用 AskUserQuestion 让用户选择保留哪个版本

## settings-hooks.json 合并算法

hooks 注册合并按 command 字段去重：
1. 读取用户现有 `.claude/settings.local.json`（如存在），提取 hooks 部分
2. 读取 `settings-hooks.json` 模板，提取要注册的 hooks
3. 对每个 hook event（SessionStart、PreToolUse 等）：
   - 用户已有的 hook command → 保留，不重复添加
   - 模板中的新 hook command → append 到对应 event 的 hooks 数组
   - 用户独有的其他配置（permissions、env 等）→ 完整保留
4. 写入合并后的完整 settings.local.json

## 重新部署

- `.story-deployed` 不存在 → 全新安装，Phase 2 全部执行
- `.story-deployed` 存在且 `agents_version: 9` → 提示已部署，AskUserQuestion 确认是否重新部署
- `.story-deployed` 存在但 `agents_version` < 9 → 提示需要更新（v9 是 breaking change：agent 引用路径改为 `<<STORY_REF>>` 占位符，必须由 setup 渲染），重新执行 Phase 2 覆盖 agents/hooks/rules + 部署 `.claude/agent-references/`；CLAUDE.md 和 settings.local.json 走合并策略

---

## 参考资料

| 文件 | 用途 |
|------|------|
| references/templates/CLAUDE.md.tmpl | 项目根 CLAUDE.md 模板 |
| references/templates/hooks/ | 6 个 hook 脚本模板 |
| references/templates/rules/ | 4 条 path-scoped 规则模板 |
| references/templates/agents/ | 7 个 agent 定义模板（story-architect, character-designer, narrative-writer, consistency-checker, story-researcher, story-explorer, chapter-extractor）。其中创作型 4 个 agent 用 `<<STORY_REF>>` 占位符引用 references，部署时由 `sed` 渲染。 |
| references/agent-references/ | Agent 模板的参考资料 canonical 副本（21 个 `.md`）；部署时复制到项目 `.claude/agent-references/`，agent 内 `<<STORY_REF>>/X.md` 在部署时被替换为 `.claude/agent-references/X.md`。 |
| references/templates/settings-hooks.json | hooks 注册 JSON 片段 |
| references/templates/上下文.md.tmpl | 写作上下文模板 |

