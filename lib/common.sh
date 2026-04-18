#!/bin/bash
# common.sh — owlwatch 共享基础：日志、配置加载、格式化、平台检测
# 纯 bash 3.2+，无外部依赖

# ─── 平台检测 ───

ow_detect_os() {
  local uname_out
  uname_out="$(uname -s)"
  case "$uname_out" in
    Darwin*) echo "macos" ;;
    Linux*)  echo "linux" ;;
    *)       echo "unknown" ;;
  esac
}

# ─── 配置加载（三级优先级：环境变量 > conf 文件 > 内置默认） ───

# 内置默认值
OW_DEFAULTS() {
  CPU_WARN_THRESHOLD=70
  MEM_WARN_THRESHOLD=80
  DISK_WARN_THRESHOLD=85
  ORPHAN_CPU_THRESHOLD=50
  ORPHAN_MIN_RUNTIME=30
  ORPHAN_PATTERNS="codex claude-mem-codex-watcher"
  PROTECT_NAMES="kernel_task WindowServer loginwindow launchd syslogd"
  DAEMON_INTERVAL=1800
  LOG_DIR="$HOME/.claude/logs"
  LOG_MAX_SIZE=1048576  # 1MB
}

# 查找 owlwatch 根目录（基于当前脚本位置）
ow_find_root() {
  local src="${BASH_SOURCE[0]}"
  while [ -L "$src" ]; do
    local dir
    dir="$(cd -P "$(dirname "$src")" && pwd)"
    src="$(readlink "$src")"
    [[ "$src" != /* ]] && src="$dir/$src"
  done
  local basedir
  basedir="$(cd -P "$(dirname "$src")" && pwd)"
  echo "$(cd "$basedir/.." && pwd)"
}

ow_load_config() {
  # 1. 加载内置默认
  OW_DEFAULTS

  # 2. 加载 conf 文件（如果存在）
  local root
  root="$(ow_find_root)"
  local conf_file="${OW_CONF:-$root/conf/owlwatch.conf}"

  if [[ -f "$conf_file" ]]; then
    # 验证配置文件：只允许 key=VALUE 格式，拒绝含命令替换的行
    local bad_line
    bad_line="$(grep -nE '`|\$\(|\|\s*' "$conf_file" | head -1)" || true
    if [[ -n "$bad_line" ]]; then
      ow_log "WARN" "配置文件包含可疑内容，跳过加载: $conf_file ($bad_line)"
    else
      # shellcheck source=/dev/null
      source "$conf_file"
    fi
  fi

  # 3. 环境变量覆盖（OW_ 前缀）— 使用 case 语句安全赋值，避免 eval 注入
  _ow_apply_env "CPU_WARN_THRESHOLD"    "${OW_CPU_WARN_THRESHOLD:-}"
  _ow_apply_env "MEM_WARN_THRESHOLD"    "${OW_MEM_WARN_THRESHOLD:-}"
  _ow_apply_env "DISK_WARN_THRESHOLD"   "${OW_DISK_WARN_THRESHOLD:-}"
  _ow_apply_env "ORPHAN_CPU_THRESHOLD"  "${OW_ORPHAN_CPU_THRESHOLD:-}"
  _ow_apply_env "ORPHAN_MIN_RUNTIME"    "${OW_ORPHAN_MIN_RUNTIME:-}"
  _ow_apply_env "ORPHAN_PATTERNS"       "${OW_ORPHAN_PATTERNS:-}"
  _ow_apply_env "PROTECT_NAMES"         "${OW_PROTECT_NAMES:-}"
  _ow_apply_env "DAEMON_INTERVAL"       "${OW_DAEMON_INTERVAL:-}"
  _ow_apply_env "LOG_DIR"               "${OW_LOG_DIR:-}"

  # 确保日志目录存在
  mkdir -p "$LOG_DIR"
}

# 安全的环境变量赋值（替代 eval）
_ow_apply_env() {
  local varname="$1" value="$2"
  [[ -z "$value" ]] && return
  case "$varname" in
    CPU_WARN_THRESHOLD)    CPU_WARN_THRESHOLD="$value" ;;
    MEM_WARN_THRESHOLD)    MEM_WARN_THRESHOLD="$value" ;;
    DISK_WARN_THRESHOLD)   DISK_WARN_THRESHOLD="$value" ;;
    ORPHAN_CPU_THRESHOLD)  ORPHAN_CPU_THRESHOLD="$value" ;;
    ORPHAN_MIN_RUNTIME)    ORPHAN_MIN_RUNTIME="$value" ;;
    ORPHAN_PATTERNS)       ORPHAN_PATTERNS="$value" ;;
    PROTECT_NAMES)         PROTECT_NAMES="$value" ;;
    DAEMON_INTERVAL)       DAEMON_INTERVAL="$value" ;;
    LOG_DIR)               LOG_DIR="$value" ;;
  esac
}

# ─── 日志 ───

ow_log() {
  local level="$1"; shift
  local msg="$*"
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  local log_file="$LOG_DIR/owlwatch.log"

  # 自动轮转
  if [[ -f "$log_file" ]]; then
    local size
    size="$(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null || echo 0)"
    if (( size > LOG_MAX_SIZE )); then
      mv "$log_file" "${log_file}.old"
    fi
  fi

  echo "[$timestamp] [$level] $msg" >> "$log_file"

  # WARN/ERROR 同时输出到 stderr
  if [[ "$level" == "WARN" || "$level" == "ERROR" ]]; then
    echo "[$level] $msg" >&2
  fi
}

# ─── 格式化工具（纯 bash，不依赖 bc） ───

ow_format_bytes() {
  local bytes="$1"
  if (( bytes >= 1073741824 )); then
    echo "$(( bytes / 1073741824 )).$(( (bytes % 1073741824) * 10 / 1073741824 )) GB"
  elif (( bytes >= 1048576 )); then
    echo "$(( bytes / 1048576 )).$(( (bytes % 1048576) * 10 / 1048576 )) MB"
  elif (( bytes >= 1024 )); then
    echo "$(( bytes / 1024 )).$(( (bytes % 1024) * 10 / 1024 )) KB"
  else
    echo "$bytes B"
  fi
}

ow_format_percent() {
  local value="$1"
  local threshold="$2"
  local label="$3"
  if (( value >= threshold )); then
    echo "⚠️  $label: ${value}% (>= ${threshold}%)"
  else
    echo "✅ $label: ${value}% (< ${threshold}%)"
  fi
}

# ─── 安全检查 ───

ow_is_protected() {
  local name="$1"
  local pattern
  for pattern in $PROTECT_NAMES; do
    if [[ "$name" == *"$pattern"* ]]; then
      return 0
    fi
  done
  return 1
}

# ─── 初始化入口 ───

ow_init() {
  ow_load_config
  ow_log "INFO" "owlwatch initialized (OS: $(ow_detect_os))"
}
