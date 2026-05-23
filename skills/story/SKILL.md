---
name: story
description: |
  网络小说工具箱主入口。用户意图模糊（不知道长短篇 / 不知道走哪个子 skill）时由此路由分发。
  触发方式：/story、/网文（不要在子意图明确时触发，子 skill 自己有触发词）
routes:
  - intent: 写长篇
    skill: story-long-write
    triggers: [开书, 写大纲, 长篇, 连载]
  - intent: 写短篇
    skill: story-short-write
    triggers: [短篇, 盐言, 一万字]
  - intent: 长篇拆文
    skill: story-long-analyze
    triggers: [拆文, 分析这本书, 黄金三章]
  - intent: 短篇拆文
    skill: story-short-analyze
    triggers: [拆短篇, 分析这个故事]
  - intent: 长篇扫榜
    skill: story-long-scan
    triggers: [长篇排行, 什么火, 起点, 番茄, 晋江]
  - intent: 短篇扫榜
    skill: story-short-scan
    triggers: [短篇排行, 知乎盐言排行]
  - intent: 去 AI 味
    skill: story-deslop
    triggers: [去 AI 味, 太 AI, 去味]
  - intent: 封面
    skill: story-cover
    triggers: [封面, 封面图]
  - intent: 环境部署
    skill: story-setup
    triggers: [准备写书, 搭环境, 初始化]
  - intent: 浏览器操控
    skill: browser-cdp
    triggers: [浏览器, 抓取, 登录态]
  - intent: 导入小说
    skill: story-import
    triggers: [导入, 反向解析, 导入小说, 把我的书导进来]
  - intent: 查故事资料
    agent: story-explorer
    triggers: [查角色, 查伏笔, 查进度, 查设定, 什么状态, 写到哪了]
  - intent: 查资料
    agent: story-researcher
    triggers: [查资料, 帮我查资料, 调研, 搜索一下, 搜一下]
---

# story：网文工具箱路由

你是网文工具箱的路由入口。用户的请求模糊时由你分发到具体 skill。

## 路由表

> 机器读取请用 frontmatter `routes`；下表是人类可读副本，由 `scripts/check-story-routes-sync.sh` 与 frontmatter 同步校验。

| 用户意图 | 关键词示例 | 路由到 |
|---|---|---|
| 写长篇 | 开书、写大纲、长篇、连载 | `/story-long-write` |
| 写短篇 | 短篇、盐言、一万字 | `/story-short-write` |
| 长篇拆文 | 拆文、分析这本书、黄金三章 | `/story-long-analyze` |
| 短篇拆文 | 拆短篇、分析这个故事 | `/story-short-analyze` |
| 长篇扫榜 | 长篇排行、什么火、起点/番茄/晋江 | `/story-long-scan` |
| 短篇扫榜 | 短篇排行、知乎盐言排行 | `/story-short-scan` |
| 去 AI 味 | 去 AI 味、太 AI、去味 | `/story-deslop` |
| 封面 | 封面、封面图 | `/story-cover` |
| 环境部署 | 准备写书、搭环境、初始化 | `/story-setup` |
| 浏览器操控 | 浏览器、抓取、登录态 | `/browser-cdp` |
| 导入小说 | 导入、反向解析、导入小说、把我的书导进来 | `/story-import` |
| 查故事资料 | 查角色、查伏笔、查进度、查设定、什么状态、写到哪了 | 直接 spawn `story-explorer` agent（使用结构化 prompt：`项目目录：{dir}\n查询类型：{根据意图选择}\n查询参数：{用户查询}`） |
| 查资料 | 查资料、帮我查资料、调研、搜索一下、搜一下 | 直接 spawn `story-researcher` agent |

## 路由流程

1. 分析用户请求，提取意图关键词
2. 匹配上表，找到对应的 skill
3. 如果能明确匹配，直接调用对应 skill（`Skill("skill-name")`）
4. 如果无法匹配，询问用户想做什么（从上表中选择）
5. 如果用户说"我想写小说"但未指定长篇/短篇，询问篇幅类型后再路由

## 项目状态感知

路由前先检查当前项目状态：

- **无项目目录**（没有包含 `追踪/` 或 `设定/` 的书名目录）：
  - 如果用户要写作，下一步是先运行 `/story-setup` 初始化环境
  - 如果用户要扫榜/拆文，直接路由
- **已有项目**：检查 `.story-deployed` 标记，如未部署则先运行 `/story-setup`
