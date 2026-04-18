#!/bin/bash
# memory.sh — owlwatch 内存/磁盘/负载分析函数
# 依赖：common.sh（ow_init 必须已调用）

# ─── 内存概况 ───
# 输出格式：total|used|free|percent|swap_total|swap_used
ow_memory_summary() {
  local os
  os="$(ow_detect_os)"

  if [[ "$os" == "macos" ]]; then
    _ow_memory_macos
  else
    _ow_memory_linux
  fi
}

_ow_memory_macos() {
  # macOS: 使用 vm_stat 和 sysctl
  local page_size
  page_size="$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)"

  local mem_total
  mem_total="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"

  # vm_stat 输出 — 用 awk 取冒号后的数字
  local vm_output
  vm_output="$(vm_stat)"

  # 各行格式如 "Pages free:                   12345."
  # 用冒号分隔，取第二部分，去除非数字字符
  local pages_free=0 pages_active=0 pages_inactive=0 pages_speculative=0 pages_wired=0

  pages_free="$(echo "$vm_output" | awk '/^Pages free/ {gsub(/[^0-9]/,"",$0); print}')"
  pages_active="$(echo "$vm_output" | awk '/^Pages active/ {gsub(/[^0-9]/,"",$0); print}')"
  pages_inactive="$(echo "$vm_output" | awk '/^Pages inactive/ {gsub(/[^0-9]/,"",$0); print}')"
  pages_speculative="$(echo "$vm_output" | awk '/^Pages speculative/ {gsub(/[^0-9]/,"",$0); print}')"
  pages_wired="$(echo "$vm_output" | awk '/^Pages wired down/ {gsub(/[^0-9]/,"",$0); print}')"

  pages_free="${pages_free:-0}"
  pages_active="${pages_active:-0}"
  pages_inactive="${pages_inactive:-0}"
  pages_speculative="${pages_speculative:-0}"
  pages_wired="${pages_wired:-0}"

  local bytes_free=$(( (pages_free + pages_speculative) * page_size ))
  local bytes_used=$(( (pages_wired + pages_active) * page_size ))

  local bytes_available=$(( (pages_inactive + pages_free + pages_speculative) * page_size ))

  local percent=0
  if (( mem_total > 0 )); then
    percent=$(( (bytes_used * 100) / mem_total ))
  fi

  # Swap 信息
  local swap_total=0 swap_used=0
  local swap_info
  swap_info="$(sysctl -n vm.swapusage 2>/dev/null || echo "")"
  if [[ -n "$swap_info" ]]; then
    swap_total="$(echo "$swap_info" | awk '{for(i=1;i<=NF;i++) if($i=="total") print $(i+2)}' | sed 's/M//' | awk '{printf "%.0f", $1 * 1048576}')"
    swap_used="$(echo "$swap_info" | awk '{for(i=1;i<=NF;i++) if($i=="used" && $(i-1)!="free") print $(i+2)}' | head -1 | sed 's/M//' | awk '{printf "%.0f", $1 * 1048576}')"
  fi

  printf "%d|%d|%d|%d|%d|%d\n" \
    "$mem_total" "$bytes_used" "$bytes_available" "$percent" "${swap_total:-0}" "${swap_used:-0}"
}

_ow_memory_linux() {
  # Linux: 解析 /proc/meminfo
  if [[ -f /proc/meminfo ]]; then
    local mem_total mem_free mem_available
    mem_total="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
    mem_free="$(awk '/MemFree/ {print $2}' /proc/meminfo)"
    mem_available="$(awk '/MemAvailable/ {print $2}' /proc/meminfo)"

    mem_total="${mem_total:-0}"
    mem_free="${mem_free:-0}"
    mem_available="${mem_available:-0}"

    local mem_used=$(( mem_total - mem_available ))
    local percent=0
    if (( mem_total > 0 )); then
      percent=$(( (mem_used * 100) / mem_total ))
    fi

    local swap_total swap_used
    swap_total="$(awk '/SwapTotal/ {print $2}' /proc/meminfo)"
    swap_free="$(awk '/SwapFree/ {print $2}' /proc/meminfo)"
    swap_total="${swap_total:-0}"
    swap_free="${swap_free:-0}"
    swap_used=$(( swap_total - swap_free ))

    # 转为字节（/proc/meminfo 单位是 kB）
    printf "%d|%d|%d|%d|%d|%d\n" \
      $(( mem_total * 1024 )) $(( mem_used * 1024 )) $(( mem_available * 1024 )) "$percent" \
      $(( swap_total * 1024 )) $(( swap_used * 1024 ))
  else
    echo "0|0|0|0|0|0"
  fi
}

# ─── 磁盘使用 ───
# 输出格式：total|used|free|percent|mount
ow_disk_usage() {
  local path="${1:-/}"
  df -h "$path" | awk -v path="$path" '
  NR == 1 { next }
  {
    total = $2
    used = $3
    free = $4
    pct = $5
    gsub(/%/, "", pct)
    mount = $NF
    printf "%s|%s|%s|%s|%s\n", total, used, free, pct, mount
  }'
}

# ─── 负载 ───
# 输出格式：load1|load5|load15|cpu_cores
ow_load_average() {
  local os
  os="$(ow_detect_os)"
  local cores

  if [[ "$os" == "macos" ]]; then
    cores="$(sysctl -n hw.ncpu 2>/dev/null || echo 1)"
  else
    cores="$(nproc 2>/dev/null || echo 1)"
  fi

  # 获取负载
  local load1 load5 load15
  if [[ "$os" == "macos" ]]; then
    local loadavg
    loadavg="$(sysctl -n vm.loadavg 2>/dev/null || echo "{ 0 0 0 }")"
    read -r _ load1 load5 load15 _ <<< "$loadavg"
  else
    read -r load1 load5 load15 _ < /proc/loadavg
  fi

  printf "%s|%s|%s|%s\n" "${load1:-0}" "${load5:-0}" "${load15:-0}" "$cores"
}
