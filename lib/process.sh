#!/bin/bash
# process.sh — owlwatch 进程分析函数
# 依赖：common.sh（ow_init 必须已调用）
# 使用 ps -eo 可靠格式，避免 ps aux 字段偏移

# ─── Top N CPU 进程 ───
# 输出格式：PID|CPU%|MEM%|RSS_MB|TT|TIME|COMMAND
ow_top_cpu() {
  local n="${1:-10}"
  ps -eo pid=%pid,pcpu=%cpu,pmem=%mem,rss=%rss,tty=%tty,time=%time,comm=%comm -r 2>/dev/null | awk -v n="$n" '
  NR == 1 { next }
  {
    printf "%s|%.1f|%.1f|%.0f|%s|%s|%s\n", $1, $2, $3, $4/1024, $5, $6, $7
  }' | head -n "$n"
}

# ─── Top N 内存进程（按应用汇总） ───
# 输出格式：APP|TOTAL_MB|COUNT
ow_top_mem() {
  local n="${1:-10}"
  ps -eo rss=%rss,comm=%comm -m 2>/dev/null | awk -v n="$n" '
  NR == 1 { next }
  {
    apps[$2] += $1
    cnt[$2]++
  }
  END {
    for (a in apps) {
      printf "%s|%.0f|%d\n", a, apps[a]/1024, cnt[a]
    }
  }' | sort -t'|' -k2 -rn | head -n "$n"
}

# ─── 孤儿进程检测 ───
# 条件：无终端绑定 + CPU > 阈值 + 运行时间 > 阈值 + 匹配模式
# 使用 ps -eo + etime 可靠格式
# 输出格式：PID|CPU%|ELAPSED|COMMAND
ow_find_orphans() {
  local awk_pattern=""
  local pat
  for pat in $ORPHAN_PATTERNS; do
    if [[ -n "$awk_pattern" ]]; then
      awk_pattern="$awk_pattern|"
    fi
    awk_pattern="${awk_pattern}^${pat}$"
  done

  local time_thresh="$ORPHAN_MIN_RUNTIME"
  local cpu_thresh="$ORPHAN_CPU_THRESHOLD"

  ps -eo pid=%pid,pcpu=%cpu,tty=%tty,etime=%etime,comm=%comm 2>/dev/null | awk -v pat="$awk_pattern" -v ct="$cpu_thresh" -v tt="$time_thresh" '
  NR == 1 { next }
  {
    pid = $1; cpu = $2; tt_field = $3; elapsed = $4; cmd = $5
    if (tt_field != "??") next
    if (pat != "" && cmd !~ pat) next
    if (cpu + 0 < ct) next

    minutes = 0
    if (index(elapsed, "-") > 0) {
      split(elapsed, dp, "-")
      days = dp[1]
      rest = dp[2]
      n = split(rest, parts, ":")
      minutes = days * 24 * 60
      if (n == 3) minutes += parts[1] * 60 + parts[2]
      else if (n == 2) minutes += parts[1]
    } else {
      n = split(elapsed, parts, ":")
      if (n == 3) minutes = parts[1] * 60 + parts[2]
      else if (n == 2) minutes = parts[1]
      else minutes = elapsed + 0
    }

    if (minutes < tt) next

    printf "%s|%.1f|%s|%s\n", pid, cpu, elapsed, cmd
  }'
}

# ─── 安全杀进程 ───
# SIGTERM → 3秒等待 → SIGKILL
ow_kill_process() {
  local pid="$1"

  local pname
  pname="$(ps -p "$pid" -o comm= 2>/dev/null | xargs basename 2>/dev/null)"
  if [[ -z "$pname" ]]; then
    echo "ERROR: PID $pid 不存在"
    return 1
  fi

  if ow_is_protected "$pname"; then
    echo "ERROR: $pname (PID $pid) 是受保护进程，拒绝杀掉"
    return 1
  fi

  ow_log "INFO" "终止进程 PID=$pid ($pname)"

  if ! kill "$pid" 2>/dev/null; then
    echo "ERROR: 无法发送 SIGTERM 到 PID $pid（权限不足？）"
    return 1
  fi

  local i
  for i in 1 2 3; do
    if ! ps -p "$pid" > /dev/null 2>&1; then
      echo "OK: PID $pid ($pname) 已终止 (SIGTERM)"
      ow_log "INFO" "PID $pid ($pname) 已终止 (SIGTERM)"
      return 0
    fi
    sleep 1
  done

  kill -9 "$pid" 2>/dev/null
  sleep 1
  if ps -p "$pid" > /dev/null 2>&1; then
    echo "ERROR: PID $pid ($pname) 无法终止（可能需要 sudo）"
    ow_log "ERROR" "PID $pid ($pname) 无法终止"
    return 1
  fi

  echo "OK: PID $pid ($pname) 已强制终止 (SIGKILL)"
  ow_log "INFO" "PID $pid ($pname) 已强制终止 (SIGKILL)"
  return 0
}

# ─── 进程树 ───
# 输出格式：PID|PPID|CPU%|MEM_MB|COMMAND
ow_process_tree() {
  local pattern="${1:-.}"
  ps -eo pid=%pid,ppid=%ppid,pcpu=%cpu,rss=%rss,comm=%comm 2>/dev/null | awk -v pat="$pattern" '
  NR == 1 { next }
  {
    pid = $1; ppid = $2; cpu = $3; rss = $4; cmd = $5
    ppid_of[pid] = ppid
    info[pid] = sprintf("%s|%.1f|%.0f|%s", ppid, cpu, rss/1024, cmd)
    cmds[pid] = cmd
    pids[++cnt] = pid
  }
  END {
    for (i = 1; i <= cnt; i++) {
      p = pids[i]
      if (cmds[p] ~ pat) {
        cur = p
        while (cur != 0 && cur != 1) {
          marked[cur] = 1
          cur = ppid_of[cur]
          if (seen[cur]++) break
        }
      }
    }
    for (i = 1; i <= cnt; i++) {
      p = pids[i]
      if (marked[p]) {
        printf "%s|%s\n", p, info[p]
      }
    }
  }'
}

# ─── 按名字杀进程 ───
ow_kill_by_name() {
  local name="$1"

  if ow_is_protected "$name"; then
    echo "ERROR: '$name' 是受保护进程，拒绝杀掉"
    return 1
  fi

  local pids
  pids="$(ps -eo pid=%pid,comm=%comm 2>/dev/null | awk -v name="$name" '$2 == name {print $1}')"

  if [[ -z "$pids" ]]; then
    echo "No processes found matching '$name'"
    return 0
  fi

  local count
  count="$(echo "$pids" | wc -l | tr -d ' ')"
  echo "Found $count process(es) matching '$name':"
  echo "$pids" | while read -r pid; do
    ow_kill_process "$pid"
  done
}
