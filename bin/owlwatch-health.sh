#!/bin/bash
# owlwatch-health.sh - System Health Report
# Usage: bash bin/owlwatch-health.sh [--json]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/process.sh"
source "$ROOT_DIR/lib/memory.sh"

ow_init

JSON_MODE=false
[[ "${1:-}" == "--json" ]] && JSON_MODE=true

separator() {
  echo "========================================================"
}

report_cpu() {
  echo ""
  echo "[CPU] Top 10"
  separator
  printf "%-8s %6s %6s %8s %-6s %-12s %s\n" "PID" "CPU%" "MEM%" "RSS(MB)" "TTY" "TIME" "COMMAND"
  separator

  local orphan_pids
  orphan_pids="$(ow_find_orphans | cut -d'|' -f1 | tr '\n' ' ')"

  ow_top_cpu 10 | while IFS='|' read -r pid cpu mem rss tt elapsed cmd; do
    local mark=""
    if [[ " $orphan_pids " == *" $pid "* ]]; then
      mark=" [ORPHAN]"
    elif [[ "$tt" == "??" ]]; then
      mark=" [bg]"
    fi
    printf "%-8s %5s%% %5s%% %8s %-6s %-12s %s%s\n" "$pid" "$cpu" "$mem" "$rss" "$tt" "$elapsed" "$cmd" "$mark"
  done || true
}

report_memory_apps() {
  echo ""
  echo "[Memory] Top 10 (by app)"
  separator
  printf "%-25s %12s %8s\n" "App" "Mem(MB)" "Procs"
  separator

  ow_top_mem 10 | while IFS='|' read -r app mem count; do
    printf "%-25s %10s MB %6s\n" "$app" "$mem" "$count"
  done
}

report_system() {
  echo ""
  echo "[System Resources]"
  separator

  local mem_info
  mem_info="$(ow_memory_summary)"
  IFS='|' read -r mem_total mem_used mem_avail mem_pct swap_total swap_used <<< "$mem_info"

  local mem_total_h mem_used_h mem_avail_h
  mem_total_h="$(ow_format_bytes "${mem_total:-0}")"
  mem_used_h="$(ow_format_bytes "${mem_used:-0}")"
  mem_avail_h="$(ow_format_bytes "${mem_avail:-0}")"

  echo "  Memory: $mem_used_h / $mem_total_h (${mem_pct:-0}%)"
  ow_format_percent "${mem_pct:-0}" "$MEM_WARN_THRESHOLD" "Memory"

  if [[ "${swap_used:-0}" -gt 0 ]] 2>/dev/null; then
    local swap_used_h swap_total_h
    swap_used_h="$(ow_format_bytes "${swap_used:-0}")"
    swap_total_h="$(ow_format_bytes "${swap_total:-0}")"
    echo "  Swap: $swap_used_h / $swap_total_h"
  fi

  echo ""
  local disk_info
  disk_info="$(ow_disk_usage /)"
  IFS='|' read -r disk_total disk_used disk_free disk_pct disk_mount <<< "$disk_info"
  echo "  Disk (${disk_mount:-/}): ${disk_used:-?} / ${disk_total:-?} (${disk_pct:-0}%)"
  ow_format_percent "${disk_pct:-0}" "$DISK_WARN_THRESHOLD" "Disk"

  echo ""
  local load_info
  load_info="$(ow_load_average)"
  IFS='|' read -r load1 load5 load15 cores <<< "$load_info"
  echo "  Load: ${load1} / ${load5} / ${load15} (${cores} cores)"

  # 纯 bash 浮点比较：去掉小数点做整数比较
  local load1_int cores_int
  load1_int="${load1%%.*}"
  cores_int="${cores%%.*}"
  load1_int="${load1_int:-0}"
  cores_int="${cores_int:-0}"
  if (( load1_int > cores_int )); then
    echo "[WARN] 1-min load (${load1}) exceeds cores (${cores}), system overloaded"
  else
    echo "[OK] Load normal"
  fi
}

report_orphans() {
  echo ""
  echo "[Orphan Process Detection]"
  separator

  local orphans
  orphans="$(ow_find_orphans)"

  if [[ -z "$orphans" ]]; then
    echo "[OK] No orphan processes found"
    return
  fi

  local count
  count="$(echo "$orphans" | wc -l | tr -d ' ')"
  echo "[WARN] Found $count orphan process(es):"
  echo ""
  printf "%-8s %6s %-12s %s\n" "PID" "CPU%" "TIME" "COMMAND"
  separator

  echo "$orphans" | while IFS='|' read -r pid cpu elapsed cmd; do
    printf "%-8s %5s%% %-12s %s\n" "$pid" "$cpu" "$elapsed" "$cmd"
  done

  echo ""
  echo "Tip: Use 'owlwatch-clean.sh --yes' to clean, or '/owlwatch clean' in Claude Code"
}

report_json() {
  local cpu_data mem_data mem_info disk_info load_info orphans

  cpu_data="$(ow_top_cpu 10)"
  mem_data="$(ow_top_mem 10)"
  mem_info="$(ow_memory_summary)"
  disk_info="$(ow_disk_usage /)"
  load_info="$(ow_load_average)"
  orphans="$(ow_find_orphans)"

  echo "{\"memory\": \"$mem_info\", \"disk\": \"$disk_info\", \"load\": \"$load_info\", \"orphans\": \"$(echo "$orphans" | tr '\n' ';')\"}"
}

main() {
  if $JSON_MODE; then
    report_json
  else
    echo ""
    echo "owlwatch - System Health Report"
    echo "  $(date '+%Y-%m-%d %H:%M:%S') | $(ow_detect_os)"
    separator

    report_cpu
    report_memory_apps
    report_system
    report_orphans

    echo ""
    separator
    echo "Report complete."
    echo ""
  fi
}

main
