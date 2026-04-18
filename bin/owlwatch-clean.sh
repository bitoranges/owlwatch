#!/bin/bash
# owlwatch-clean.sh — 孤儿进程清理
# 用法：
#   bash bin/owlwatch-clean.sh              # 仅检测，不杀
#   bash bin/owlwatch-clean.sh --yes        # 自动杀掉所有检测到的孤儿
#   bash bin/owlwatch-clean.sh --pid 12345  # 杀指定 PID

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"
# shellcheck source=../lib/process.sh
source "$ROOT_DIR/lib/process.sh"

ow_init

AUTO_YES=false
TARGET_PID=""
TARGET_NAME=""

# 参数解析
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y)    AUTO_YES=true; shift ;;
    --pid|-p)    TARGET_PID="$2"; shift 2 ;;
    --name|-n)   TARGET_NAME="$2"; shift 2 ;;
    --help|-h)
      echo "用法: owlwatch-clean.sh [--yes] [--pid PID] [--name NAME]"
      echo "  --yes       自动清理所有检测到的孤儿进程"
      echo "  --pid N     只清理指定 PID"
      echo "  --name STR  按进程名精确匹配清理"
      echo "  无参数      仅检测，不执行清理"
      exit 0
      ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

echo ""
echo "🧹 owlwatch — 孤儿进程清理"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ─── 指定 PID 模式 ───
if [[ -n "$TARGET_PID" ]]; then
  echo "指定 PID: $TARGET_PID"
  echo ""
  ow_kill_process "$TARGET_PID"
  exit $?
fi

# ─── 按名字杀模式 ───
if [[ -n "$TARGET_NAME" ]]; then
  echo "按名字杀: $TARGET_NAME"
  echo ""
  ow_kill_by_name "$TARGET_NAME"
  exit $?
fi

# ─── 扫描孤儿 ───
echo "Scanning..."
orphans="$(ow_find_orphans)"

if [[ -z "$orphans" ]]; then
  echo "[OK] No orphan processes found"
  exit 0
fi

count="$(echo "$orphans" | wc -l | tr -d ' ')"
echo ""
echo "⚠️  发现 $count 个孤儿进程："
echo ""
printf "%-8s %8s %-12s %s\n" "PID" "CPU%" "ELAPSED" "COMMAND"
echo "──────────────────────────────────────────────────"
echo "$orphans" | while IFS='|' read -r pid cpu elapsed cmd; do
  printf "%-8s %7s%% %-12s %s\n" "$pid" "$cpu" "$elapsed" "$cmd"
done

# ─── 清理 ───
if ! $AUTO_YES; then
  echo ""
  echo "💡 这是检测模式，未执行清理。使用 --yes 自动清理，或在 Claude Code 中执行 /owlwatch clean"
  exit 0
fi

echo ""
echo "开始清理..."
echo ""

cleaned=0
failed=0
while IFS='|' read -r pid cpu elapsed cmd; do
  echo "终止 PID $pid ($cmd)..."
  if ow_kill_process "$pid"; then
    cleaned=$((cleaned + 1))
  else
    failed=$((failed + 1))
  fi
done <<< "$orphans"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧹 清理完成: 成功 $cleaned, 失败 $failed"
