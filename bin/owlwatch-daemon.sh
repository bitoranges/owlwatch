#!/bin/bash
# owlwatch-daemon.sh — launchd 后台守护进程管理
# 用法：
#   bash bin/owlwatch-daemon.sh install    # 安装 launchd 守护进程
#   bash bin/owlwatch-daemon.sh uninstall  # 卸载
#   bash bin/owlwatch-daemon.sh status     # 查看状态

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"

ow_init

PLIST_NAME="com.ryan.owlwatch"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$PLIST_DIR/$PLIST_NAME.plist"
CLEAN_SCRIPT="$ROOT_DIR/bin/owlwatch-clean.sh"
LOG_STDOUT="$LOG_DIR/owlwatch-daemon-stdout.log"
LOG_STDERR="$LOG_DIR/owlwatch-daemon-stderr.log"

# ─── 生成 plist ───
generate_plist() {
  cat <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_NAME</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$CLEAN_SCRIPT</string>
        <string>--yes</string>
    </array>
    <key>StartInterval</key>
    <integer>$DAEMON_INTERVAL</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG_STDOUT</string>
    <key>StandardErrorPath</key>
    <string>$LOG_STDERR</string>
</dict>
</plist>
PLISTEOF
}

# ─── 安装 ───
do_install() {
  if [[ "$(ow_detect_os)" != "macos" ]]; then
    echo "ERROR: Daemon 模式仅支持 macOS（使用 launchd）"
    exit 1
  fi

  # 检查是否已有旧的 orphan-reaper
  local old_plist="$PLIST_DIR/com.ryan.orphan-reaper.plist"
  if [[ -f "$old_plist" ]]; then
    echo "⚠️  检测到旧版 orphan-reaper，正在迁移..."
    launchctl unload "$old_plist" 2>/dev/null || true
    mv "$old_plist" "${old_plist}.bak"
    echo "   旧配置已备份到 ${old_plist}.bak"
  fi

  if [[ -f "$PLIST_PATH" ]]; then
    echo "owlwatch daemon 已安装，正在更新..."
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
  fi

  mkdir -p "$PLIST_DIR"
  generate_plist > "$PLIST_PATH"

  launchctl load "$PLIST_PATH"

  echo "✅ owlwatch daemon 已安装并启动"
  echo "   间隔：每 $(( DAEMON_INTERVAL / 60 )) 分钟自动清理孤儿进程"
  echo "   日志：$LOG_STDOUT"
  echo "   plist：$PLIST_PATH"
}

# ─── 卸载 ───
do_uninstall() {
  if [[ ! -f "$PLIST_PATH" ]]; then
    echo "owlwatch daemon 未安装"
    exit 0
  fi

  launchctl unload "$PLIST_PATH" 2>/dev/null || true
  rm "$PLIST_PATH"

  echo "✅ owlwatch daemon 已卸载"
}

# ─── 状态 ───
do_status() {
  echo "🦉 owlwatch daemon 状态"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if [[ ! -f "$PLIST_PATH" ]]; then
    echo "  未安装"
    echo "  使用 owlwatch-daemon.sh install 安装"
    exit 0
  fi

  echo "  plist：$PLIST_PATH"
  echo "  间隔：每 $(( DAEMON_INTERVAL / 60 )) 分钟"

  if launchctl list | grep -q "$PLIST_NAME" 2>/dev/null; then
    local pid
    pid="$(launchctl list | grep "$PLIST_NAME" | awk '{print $1}')"
    echo "  状态：运行中（PID: ${pid:-N/A}）"
  else
    echo "  状态：已安装但未运行（可能需要 launchctl load）"
  fi

  echo "  日志：$LOG_STDOUT"
  if [[ -f "$LOG_STDOUT" ]]; then
    echo ""
    echo "  最近 5 条日志："
    tail -5 "$LOG_STDOUT" | while read -r line; do
      echo "    $line"
    done
  fi
}

# ─── 主入口 ───
case "${1:-status}" in
  install)    do_install ;;
  uninstall)  do_uninstall ;;
  status)     do_status ;;
  *)
    echo "用法: owlwatch-daemon.sh {install|uninstall|status}"
    exit 1
    ;;
esac
