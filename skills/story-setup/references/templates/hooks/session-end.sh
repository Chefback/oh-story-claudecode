#!/bin/bash
# session-end.sh — 会话结束时记录最后状态
# 设计原则：静默执行，不输出任何内容
set -euo pipefail

# 加载公共函数库
source "$(dirname "$0")/lib/common.sh"

# 默认禁用 session-log.txt 写入 (积少成多会污染 追踪/, 大多数用户不需要)
# 显式 STORY_SESSION_LOG=1 才启用; export 到 shell rc 或 .claude/settings.local.json env.
if [ "${STORY_SESSION_LOG:-0}" != "1" ]; then
  exit 0
fi

BOOK_DIR=$(discover_active_book)

# 记录会话结束时间戳
if [ -n "$BOOK_DIR" ]; then
  mkdir -p "$BOOK_DIR/追踪"
  echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] session ended" >> "$BOOK_DIR/追踪/session-log.txt"
fi
