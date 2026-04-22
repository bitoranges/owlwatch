#!/bin/bash
# owlwatch-doctor.sh — Dev Environment Check
# Usage: bash bin/owlwatch-doctor.sh [--detail|--json|--all|--help]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/doctor.sh"

ow_init

MODE="summary"

show_doctor_help() {
  cat <<EOF
owlwatch doctor — Dev Environment Check

Usage:
  owlwatch doctor [options]

Options:
  (no option)        Summary score and status per dimension
  --detail           Full detail with sub-items per dimension
  --json             JSON output
  --all              Combined health + doctor report
  --help             Show this help

Checks 15 dimensions:
  Tools, Model Config, MCP Servers, Permissions, Hooks,
  Skills, Agents, Rules, Memory, Project Context,
  Context Hygiene, Git, Terminal, Security, Cost Efficiency

Examples:
  owlwatch doctor                  # Quick summary
  owlwatch doctor --detail         # Full report
  owlwatch doctor --json           # JSON output
EOF
}

# 解析参数
while [[ $# -gt 0 ]]; do
  case "$1" in
    --detail|-d) MODE="detail" ;;
    --json|-j)   MODE="json" ;;
    --all|-a)    MODE="combined" ;;
    --help|-h)   show_doctor_help; exit 0 ;;
    *) echo "Unknown option: $1"; echo "Run 'owlwatch doctor --help' for usage."; exit 1 ;;
  esac
  shift
done

main() {
  # 执行所有检查
  owd_run_all_checks

  case "$MODE" in
    summary)
      echo ""
      echo "🦉 owlwatch doctor — Dev Environment Check"
      echo "  $(date '+%Y-%m-%d %H:%M') | $(ow_detect_os)"
      echo "========================================================"
      owd_report_summary
      echo ""
      echo "Run 'owlwatch doctor --detail' for full report"
      echo "========================================================"
      echo ""
      ;;
    detail)
      echo ""
      echo "🦉 owlwatch doctor — Dev Environment Check (Detail)"
      echo "  $(date '+%Y-%m-%d %H:%M') | $(ow_detect_os)"
      echo "========================================================"
      echo ""
      echo "Score: $OWD_TOTAL_SCORE/$OWD_TOTAL_MAX"
      owd_report_detail
      echo ""
      echo "========================================================"
      echo ""
      ;;
    json)
      owd_report_json
      ;;
    combined)
      owd_report_combined
      echo "========================================================"
      echo ""
      ;;
  esac
}

main
