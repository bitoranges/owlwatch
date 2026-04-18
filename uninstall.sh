#!/bin/bash
# uninstall.sh — owlwatch 卸载脚本
# 用法：bash uninstall.sh [--claude | --standalone | --all]

set -euo pipefail

MODE="${1:---claude}"

if [[ "$MODE" == "--all" ]]; then
  echo ""
  echo "Removing owlwatch (all modes)..."
  rm -rf "$HOME/.claude/skills/owlwatch"
  rm -f "$HOME/.local/bin/owlwatch-"*.sh
  rm -rf "$HOME/.local/share/owlwatch"
  echo "Done."
  exit 0
fi

echo ""
echo "owlwatch uninstaller"
echo "===================="

if [[ "$MODE" == "--standalone" ]]; then
  echo "Removing standalone installation..."
  rm -f "$HOME/.local/bin/owlwatch-"*.sh
  rm -rf "$HOME/.local/share/owlwatch"
else
  echo "Removing Claude Code skill..."
  rm -rf "$HOME/.claude/skills/owlwatch"
fi

echo "Done."
echo ""
echo "Note: Logs in ~/.claude/logs/ are preserved."
echo "Note: Daemon plist (if installed) is preserved; run owlwatch-daemon.sh uninstall first."
echo ""
