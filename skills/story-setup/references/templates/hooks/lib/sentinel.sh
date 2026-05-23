#!/bin/bash
# sentinel.sh — 读取 .story-deployed sentinel 字段的工具函数
# .story-deployed 是 YAML key: value 格式（不依赖 yq，用 awk 单进程解析）
# 注意：不加 set -euo pipefail，避免 source 时覆盖调用方的 shell options

SENTINEL_FILE="${SENTINEL_FILE:-.story-deployed}"

# read_sentinel_field <field_name> [file]
# 输出字段值（已去除前后空格和成对引号）；文件或字段缺失时输出空串。
# 调用方安全：始终 return 0，不会因 pipefail / set -e 导致 caller 退出。
# 字段名约定：必须是 YAML key 字面量（[A-Za-z_][A-Za-z0-9_]*），不做正则元字符转义。
# 用法：
#   AV=$(read_sentinel_field agents_version)
#   TC=$(read_sentinel_field target_cli)
read_sentinel_field() {
  local field="$1"
  local file="${2:-$SENTINEL_FILE}"
  [ -f "$file" ] || return 0
  # 单进程 awk：用 substr 字面量前缀比较，避免正则元字符；找到首行后 exit，
  # 不接 head/sed 管道，杜绝 SIGPIPE 在 pipefail 下打死调用方。
  awk -v key="${field}:" '
    { sub(/\r$/, "") }
    substr($0, 1, length(key)) == key {
      v = substr($0, length(key) + 1)
      sub(/^[[:space:]]+/, "", v)
      n = length(v)
      if (n >= 2 && substr(v, 1, 1) == "\"" && substr(v, n, 1) == "\"") {
        v = substr(v, 2, n - 2)
      } else if (n >= 2) {
        q = sprintf("%c", 39)
        if (substr(v, 1, 1) == q && substr(v, n, 1) == q) {
          v = substr(v, 2, n - 2)
        }
      }
      sub(/[[:space:]]+$/, "", v)
      print v
      exit
    }
  ' "$file" 2>/dev/null
  return 0
}

# sentinel_exists [file] — exit 0 / 1
sentinel_exists() {
  [ -f "${1:-$SENTINEL_FILE}" ]
}
