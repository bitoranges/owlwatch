#!/bin/bash
# install.sh — owlwatch 安装脚本
# 用法：bash install.sh [--claude | --standalone]
#   --claude    安装到 ~/.claude/skills/owlwatch/（默认）
#   --standalone 安装到 ~/.local/bin/（仅命令行使用）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE="claude"

if [[ "${1:-}" == "--standalone" ]]; then
  MODE="standalone"
fi

echo ""
echo "owlwatch installer"
echo "=================="

# ─── Claude Code skill 模式 ───
if [[ "$MODE" == "claude" ]]; then
  TARGET="$HOME/.claude/skills/owlwatch"

  echo "Mode: Claude Code skill"
  echo "Target: $TARGET"
  echo ""

  # 备份旧配置（如果存在）
  local conf_backup=""
  if [[ -f "$TARGET/conf/owlwatch.conf" ]]; then
    echo "Preserving existing config..."
    conf_backup="$(mktemp)"
    cp "$TARGET/conf/owlwatch.conf" "$conf_backup"
  fi

  # 复制文件
  mkdir -p "$TARGET"/{bin,lib,conf}
  cp "$SCRIPT_DIR"/bin/*.sh "$TARGET/bin/"
  cp "$SCRIPT_DIR"/lib/*.sh "$TARGET/lib/"
  cp "$SCRIPT_DIR/conf/owlwatch.conf.example" "$TARGET/conf/"

  # 恢复配置（如果之前有）
  if [[ -n "$conf_backup" ]] && [[ -f "$conf_backup" ]]; then
    cp "$conf_backup" "$TARGET/conf/owlwatch.conf"
    rm -f "$conf_backup"
    echo "Restored existing config."
  else
    # 首次安装：复制示例配置
    if [[ ! -f "$TARGET/conf/owlwatch.conf" ]]; then
      cp "$TARGET/conf/owlwatch.conf.example" "$TARGET/conf/owlwatch.conf"
    fi
  fi

  # 复制 SKILL.md（Claude Code 注册入口）
  cp "$SCRIPT_DIR/SKILL.md" "$TARGET/"

  # 设置执行权限
  chmod +x "$TARGET"/bin/*.sh

  echo ""
  echo "Installed successfully!"
  echo ""
  echo "Usage:"
  echo "  /owlwatch          # In Claude Code"
  echo "  bash $TARGET/bin/owlwatch-health.sh   # Direct"
  echo ""

# ─── Standalone 模式 ───
else
  TARGET="$HOME/.local/bin"
  mkdir -p "$TARGET"

  echo "Mode: Standalone"
  echo "Target: $TARGET"
  echo ""

  # 复制所有脚本到 ~/.local/bin
  for script in "$SCRIPT_DIR"/bin/owlwatch-*.sh; do
    script_name="$(basename "$script")"
    cp "$script" "$TARGET/"
    chmod +x "$TARGET/$script_name"
    echo "  Installed: $TARGET/$script_name"
  done

  # 复制 lib 和 conf 到 ~/.local/share/owlwatch
  SHARE_DIR="$HOME/.local/share/owlwatch"
  mkdir -p "$SHARE_DIR"/{lib,conf}
  cp "$SCRIPT_DIR"/lib/*.sh "$SHARE_DIR/lib/"
  cp "$SCRIPT_DIR/conf/owlwatch.conf.example" "$SHARE_DIR/conf/"
  [[ ! -f "$SHARE_DIR/conf/owlwatch.conf" ]] && \
    cp "$SHARE_DIR/conf/owlwatch.conf.example" "$SHARE_DIR/conf/owlwatch.conf"

  # 修改脚本中的路径指向安装位置
  for script in "$TARGET"/owlwatch-*.sh; do
    if grep -q 'ROOT_DIR=' "$script" 2>/dev/null; then
      sed -i.bak "s|ROOT_DIR=.*|ROOT_DIR=\"$SHARE_DIR\"|" "$script"
      rm -f "${script}.bak"
    fi
  done

  echo ""
  echo "Installed successfully!"
  echo ""
  echo "Usage:"
  echo "  owlwatch-health.sh"
  echo "  owlwatch-clean.sh --yes"
  echo "  owlwatch-chrome.sh"
  echo ""
fi
