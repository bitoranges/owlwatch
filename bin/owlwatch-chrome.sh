#!/bin/bash
# owlwatch-chrome.sh - Chrome Analysis Report
# Usage: bash bin/owlwatch-chrome.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/chrome.sh"

ow_init

echo ""
echo "owlwatch - Chrome Analysis"
echo "========================================================"

# Check if Chrome is running
if ! pgrep -x "Google Chrome" > /dev/null 2>&1; then
  echo "Chrome is not currently running"
  exit 0
fi

# ─── Memory Usage ───
echo ""
echo "[Chrome Memory]"
echo "--------------------------------------------------------"

chrome_mem="$(ow_chrome_memory)"
IFS='|' read -r total renderers gpu ext_count tab_est <<< "$chrome_mem"

echo "  Total: ${total} MB"
echo "  Tab renderers: ${renderers} MB (~${tab_est} tabs)"
echo "  GPU process: ${gpu} MB"
echo "  Extension renderers: ${ext_count}"

if (( total > 4096 )); then
  echo "[CRITICAL] Chrome using >4GB, consider cleanup"
elif (( total > 2048 )); then
  echo "[WARN] Chrome using >2GB, consider closing tabs"
else
  echo "[OK] Chrome memory usage normal"
fi

# ─── Process Distribution ───
echo ""
echo "[Chrome Process Distribution]"
echo "--------------------------------------------------------"

proc_types="$(ps aux | awk '/[G]oogle Chrome/ {
  cmd = ""
  for (i=11; i<=NF; i++) cmd = cmd " " $i
  if (cmd ~ /--type=renderer/) {
    if (cmd ~ /--extension-process/) {
      ext_rss += $6; ext_cnt++
    } else {
      tab_rss += $6; tab_cnt++
    }
  } else if (cmd ~ /--type=gpu-process/) {
    gpu_rss += $6; gpu_cnt++
  } else if (cmd ~ /--type=utility/) {
    util_rss += $6; util_cnt++
  } else {
    main_rss += $6; main_cnt++
  }
}
END {
  printf "Tabs|%d|%.0f\n", tab_cnt, tab_rss/1024
  printf "Extensions|%d|%.0f\n", ext_cnt, ext_rss/1024
  printf "GPU|%d|%.0f\n", gpu_cnt, gpu_rss/1024
  printf "Utility|%d|%.0f\n", util_cnt, util_rss/1024
  printf "Main|%d|%.0f\n", main_cnt, main_rss/1024
}')"

printf "%-12s %8s %12s\n" "Type" "Procs" "Mem(MB)"
echo "--------------------------------------------------------"
echo "$proc_types" | while IFS='|' read -r type cnt mem; do
  printf "%-12s %6s %10s MB\n" "$type" "$cnt" "$mem"
done

# ─── Extensions ───
echo ""
echo "[Installed Extensions]"
echo "--------------------------------------------------------"

extensions="$(ow_chrome_extensions)"

if [[ "$extensions" == INFO:* ]]; then
  echo "  $extensions"
elif [[ -z "$extensions" ]]; then
  echo "  No extensions found"
else
  echo "$extensions" | while IFS='|' read -r ext_id name version; do
    printf "  %-30s %s\n" "$name" "v$version"
  done
fi

echo ""
echo "========================================================"
echo "Chrome analysis complete."
echo ""
