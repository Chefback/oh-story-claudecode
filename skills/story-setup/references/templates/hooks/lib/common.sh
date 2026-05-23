#!/bin/bash
# common.sh — 公共函数库，供各 hook 文件 source
# 注意：不加 set -euo pipefail，避免 source 时覆盖调用方的 shell options

# discover_active_book — 单本书查询（活跃书目）
# 优先 .active-book 文件；其次 find 第一个 追踪/ (长篇) 或 正文/ (短篇) 目录
# 使用场景：session-start / session-end / pre-compact / post-compact —— 一次会话只关心当前活跃的那本书
discover_active_book() {
  if [ -f ".active-book" ]; then
    cat ".active-book"
    return
  fi
  local root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  # 长篇优先（追踪/ 目录存在）
  local first=$(find "$root" -maxdepth 4 -type d -name "追踪" -print -quit 2>/dev/null || true)
  if [ -n "$first" ]; then
    dirname "$first"
    return
  fi
  # 短篇 fallback：查找 正文/ 目录（maxdepth 4 覆盖 推荐/短篇/书名/正文 结构）
  local story_dir=$(find "$root" -maxdepth 4 -type d -name "正文" -print -quit 2>/dev/null || true)
  if [ -n "$story_dir" ]; then
    dirname "$story_dir"
  fi
}

# discover_all_books — 多本书查询（项目内所有书目）
# 输出：换行分隔的目录路径列表（不含重复）
# 使用场景：detect-story-gaps —— 需要遍历项目内所有书目做缺口检测
discover_all_books() {
  local root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  # 用 awk 去重保持插入顺序（bash 3.2 兼容，不用关联数组）
  {
    # 长篇：追踪/ 父目录
    find "$root" -maxdepth 4 -type d -name "追踪" -print 2>/dev/null | while IFS= read -r d; do dirname "$d"; done
    # 短篇：正文/ 父目录 或 正文.md 父目录
    find "$root" -maxdepth 3 \( -type d -name "正文" -o -type f -name "正文.md" \) -print 2>/dev/null | while IFS= read -r d; do dirname "$d"; done
  } | awk '!seen[$0]++'
}

# 旧名 alias，仅供外部自定义 hook 引用；新代码用 discover_active_book / discover_all_books。
discover_book_dir() {
  discover_active_book "$@"
}
