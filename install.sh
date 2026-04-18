#!/bin/bash
# install.sh — owlwatch installer
# Usage: bash install.sh [OPTIONS]
#   (default)          Install CLI to ~/.local/bin
#   --claude           Also install as Claude Code skill
#   --cursor           Print Cursor rules setup instructions
#   --windsurf         Print Windsurf rules setup instructions
#   --uninstall        Remove owlwatch

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_CLAUDE=false
INSTALL_CURSOR=false
INSTALL_WINDSURF=false

for arg in "$@"; do
  case "$arg" in
    --claude)   INSTALL_CLAUDE=true ;;
    --cursor)   INSTALL_CURSOR=true ;;
    --windsurf) INSTALL_WINDSURF=true ;;
    --uninstall)
      echo "Removing owlwatch..."
      rm -f "$HOME/.local/bin/owlwatch"
      rm -f "$HOME/.local/bin/owlwatch-"*.sh
      rm -rf "$HOME/.local/share/owlwatch"
      rm -rf "$HOME/.claude/skills/owlwatch"
      echo "Done."
      exit 0
      ;;
    --help|-h)
      echo "Usage: bash install.sh [--claude] [--cursor] [--windsurf] [--uninstall]"
      exit 0
      ;;
  esac
done

echo ""
echo "owlwatch installer"
echo "=================="

# ─── 1. Standalone CLI（默认必装） ───

BIN_DIR="$HOME/.local/bin"
SHARE_DIR="$HOME/.local/share/owlwatch"

mkdir -p "$BIN_DIR"
mkdir -p "$SHARE_DIR"/{lib,conf}

# 复制主入口和子脚本
cp "$SCRIPT_DIR/bin/owlwatch" "$BIN_DIR/"
chmod +x "$BIN_DIR/owlwatch"

for script in "$SCRIPT_DIR"/bin/owlwatch-*.sh; do
  [[ -f "$script" ]] || continue
  cp "$script" "$SHARE_DIR/bin-temp/" 2>/dev/null || true
done

# lib 和 conf
cp "$SCRIPT_DIR"/lib/*.sh "$SHARE_DIR/lib/"
cp "$SCRIPT_DIR/conf/owlwatch.conf.example" "$SHARE_DIR/conf/"
[[ ! -f "$SHARE_DIR/conf/owlwatch.conf" ]] && \
  cp "$SHARE_DIR/conf/owlwatch.conf.example" "$SHARE_DIR/conf/owlwatch.conf"

# 复制子脚本到 share 目录，主入口直接调用
mkdir -p "$SHARE_DIR/bin"
cp "$SCRIPT_DIR"/bin/owlwatch-*.sh "$SHARE_DIR/bin/"
chmod +x "$SHARE_DIR/bin/"*.sh

# 修改主入口中的 SCRIPT_DIR 指向 share 目录
if grep -q 'SCRIPT_DIR=' "$BIN_DIR/owlwatch" 2>/dev/null; then
  sed -i.bak "s|SCRIPT_DIR=\".*\"|SCRIPT_DIR=\"$SHARE_DIR/bin\"|" "$BIN_DIR/owlwatch"
  sed -i.bak "s|ROOT_DIR=\".*\"|ROOT_DIR=\"$SHARE_DIR\"|" "$BIN_DIR/owlwatch"
  rm -f "$BIN_DIR/owlwatch.bak"
fi

# 修改子脚本中的 ROOT_DIR
for script in "$SHARE_DIR/bin"/owlwatch-*.sh; do
  if grep -q 'ROOT_DIR=' "$script" 2>/dev/null; then
    sed -i.bak "s|ROOT_DIR=\".*\"|ROOT_DIR=\"$SHARE_DIR\"|" "$script"
    rm -f "${script}.bak"
  fi
done

echo "  CLI installed to $BIN_DIR/owlwatch"
echo "  Data in $SHARE_DIR/"

# 确保 ~/.local/bin 在 PATH
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  echo ""
  echo "  NOTE: Add ~/.local/bin to your PATH:"
  echo "    echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
  echo "    source ~/.bashrc"
fi

# ─── 2. Claude Code skill（可选） ───

if $INSTALL_CLAUDE; then
  CLAUDE_DIR="$HOME/.claude/skills/owlwatch"
  conf_backup=""
  if [[ -f "$CLAUDE_DIR/conf/owlwatch.conf" ]]; then
    conf_backup="$(mktemp)"
    cp "$CLAUDE_DIR/conf/owlwatch.conf" "$conf_backup"
  fi

  mkdir -p "$CLAUDE_DIR"/{bin,lib,conf}
  cp "$SCRIPT_DIR"/bin/owlwatch "$CLAUDE_DIR/bin/"
  cp "$SCRIPT_DIR"/bin/*.sh "$CLAUDE_DIR/bin/"
  cp "$SCRIPT_DIR"/lib/*.sh "$CLAUDE_DIR/lib/"
  cp "$SCRIPT_DIR/conf/owlwatch.conf.example" "$CLAUDE_DIR/conf/"
  chmod +x "$CLAUDE_DIR/bin/"*

  if [[ -n "$conf_backup" ]] && [[ -f "$conf_backup" ]]; then
    cp "$conf_backup" "$CLAUDE_DIR/conf/owlwatch.conf"
    rm -f "$conf_backup"
  else
    [[ ! -f "$CLAUDE_DIR/conf/owlwatch.conf" ]] && \
      cp "$CLAUDE_DIR/conf/owlwatch.conf.example" "$CLAUDE_DIR/conf/owlwatch.conf"
  fi

  # 安装 SKILL.md
  if [[ -f "$SCRIPT_DIR/adapters/claude-code.md" ]]; then
    cp "$SCRIPT_DIR/adapters/claude-code.md" "$CLAUDE_DIR/SKILL.md"
  fi

  echo "  Claude Code skill installed to $CLAUDE_DIR/"
fi

# ─── 3. Cursor / Windsurf 提示 ───

if $INSTALL_CURSOR; then
  echo ""
  echo "  Cursor setup:"
  echo "    cp $SCRIPT_DIR/adapters/cursor.md .cursor/rules/owlwatch.md"
fi

if $INSTALL_WINDSURF; then
  echo ""
  echo "  Windsurf setup:"
  echo "    cat $SCRIPT_DIR/adapters/windsurf.md >> .windsurfrules"
fi

echo ""
echo "Done! Run: owlwatch health"
echo ""
