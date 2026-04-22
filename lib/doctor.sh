#!/bin/bash
# doctor.sh — owlwatch 开发环境体检核心库
# 依赖：common.sh（ow_init 必须已调用）
# 纯 bash/awk，零外部依赖

# ─── 全局状态 ───

OWD_RESULTS=()        # 每项: "func_name|status|score|max|summary"
OWD_DETAILS=()        # 每项: "func_name|detail_lines"
OWD_TOTAL_SCORE=0
OWD_TOTAL_MAX=112

# ─── 辅助函数 ───

# 从 JSON 文件提取 key 的值（字符串/布尔/数字）
_owd_json_value() {
  local file="$1" key="$2"
  [[ ! -f "$file" ]] && return 1
  awk -v k="\"$key\"" '
  {
    idx = index($0, k)
    if (idx == 0) next
    rest = substr($0, idx + length(k))
    gsub(/^[ \t]*:[ \t]*/, "", rest)
    if (substr(rest,1,1) == "\"") {
      gsub(/^"/, "", rest)
      gsub(/".*/, "", rest)
    } else {
      gsub(/[,} \t].*/, "", rest)
    }
    print rest
    exit
  }' "$file"
}

# 计数 JSON 数组中的元素
_owd_json_array_count() {
  local file="$1" key="$2"
  [[ ! -f "$file" ]] && echo 0 && return
  awk -v k="\"$key\"" '
  BEGIN { in_arr = 0; depth = 0; count = 0 }
  {
    idx = index($0, k)
    if (idx > 0) {
      rest = substr($0, idx + length(k))
      gsub(/^[^[]*/, "", rest)
      if (substr(rest,1,1) == "[") in_arr = 1
    }
    if (!in_arr) next
    n = split($0, chars, "")
    for (i = 1; i <= n; i++) {
      if (chars[i] == "[") depth++
      if (chars[i] == "]") { depth--; if (depth == 0) { print count; exit } }
      if (depth == 1 && chars[i] == "," && i > 1) count++
    }
  }
  END { if (in_arr && depth > 0) print count + 1 }' "$file"
}

# 检测命令是否存在
_owd_has_cmd() {
  command -v "$1" &>/dev/null
}

# 检测文件存在且非空
_owd_has_file() {
  [[ -f "$1" && -s "$1" ]]
}

# 估算文件 token 数（按 ~4 字符/token）
_owd_estimate_tokens() {
  local path="$1"
  [[ ! -f "$path" ]] && echo 0 && return
  local bytes
  bytes="$(wc -c < "$path" 2>/dev/null || echo 0)"
  echo $(( bytes / 4 ))
}

# 获取 settings.json 路径
_owd_settings_path() {
  local p="$HOME/.claude/settings.json"
  [[ -f "$p" ]] && echo "$p" && return
  p="$HOME/.claude/settings.local.json"
  [[ -f "$p" ]] && echo "$p" && return
  echo ""
}

# ─── 15 个维度检查 ───
# 每个函数设置 _OWD_STATUS / _OWD_SCORE / _OWD_MAX / _OWD_SUMMARY / _OWD_DETAIL

# 1. 工具链可用性 (10分)
owd_check_tools() {
  _OWD_MAX=10
  local tools="claude codex cursor windsurf node python3 go git gh tmux"
  local found=0 total=0 detail=""

  for t in $tools; do
    total=$((total + 1))
    if _owd_has_cmd "$t"; then
      found=$((found + 1))
      detail+="  ✅ $t\n"
    else
      detail+="  ❌ $t (not found)\n"
    fi
  done

  _OWD_SCORE=$(( found * _OWD_MAX / total ))
  _OWD_DETAIL="$detail"

  if (( found >= total - 2 )); then
    _OWD_STATUS="pass"
    _OWD_SUMMARY="$found/$total tools available"
  elif (( found >= total / 2 )); then
    _OWD_STATUS="warn"
    _OWD_SUMMARY="$found/$total tools available, some missing"
  else
    _OWD_STATUS="fail"
    _OWD_SUMMARY="Only $found/$total tools available"
  fi
}

# 2. 模型配置 (7分)
owd_check_model_config() {
  _OWD_MAX=7
  local sp
  sp="$(_owd_settings_path)"
  _OWD_DETAIL=""

  if [[ -z "$sp" ]]; then
    _OWD_STATUS="fail"
    _OWD_SCORE=0
    _OWD_SUMMARY="No settings.json found"
    _OWD_DETAIL="  ❌ ~/.claude/settings.json not found\n"
    return
  fi

  local issues=0
  local model
  model="$(_owd_json_value "$sp" "model")"
  if [[ -n "$model" ]]; then
    _OWD_DETAIL+="  ✅ Model: $model\n"
  else
    _OWD_DETAIL+="  ⚠️  No model preference set (uses default)\n"
    issues=$((issues + 1))
  fi

  local thinking
  thinking="$(_owd_json_value "$sp" "alwaysThinkingEnabled")"
  if [[ "$thinking" == "true" ]]; then
    _OWD_DETAIL+="  ✅ Extended thinking: enabled\n"
  else
    _OWD_DETAIL+="  ⚠️  Extended thinking: not enabled\n"
    issues=$((issues + 1))
  fi

  local ctx_budget
  ctx_budget="$(_owd_json_value "$sp" "contextBudget")"
  if [[ -n "$ctx_budget" ]]; then
    _OWD_DETAIL+="  ✅ Context budget: $ctx_budget\n"
  else
    _OWD_DETAIL+="  ℹ️  Context budget: default\n"
  fi

  if (( issues == 0 )); then
    _OWD_STATUS="pass"
    _OWD_SCORE=$_OWD_MAX
    _OWD_SUMMARY="Model: ${model:-default}, thinking: ${thinking:-off}"
  elif (( issues == 1 )); then
    _OWD_STATUS="warn"
    _OWD_SCORE=$(( _OWD_MAX / 2 ))
    _OWD_SUMMARY="Model: ${model:-default}, $issues config gap"
  else
    _OWD_STATUS="warn"
    _OWD_SCORE=$(( _OWD_MAX * 3 / 10 ))
    _OWD_SUMMARY="$issues configuration gaps"
  fi
}

# 3. MCP Servers (8分) — 检查多个配置来源，提取 server 名和 command
owd_check_mcp_servers() {
  _OWD_MAX=8
  _OWD_DETAIL=""
  local mcp_count=0 unreachable=0

  # 提取 MCP server 名字和 command 值（支持多行 JSON）
  _owd_extract_mcp_servers() {
    local cfg="$1"
    [[ ! -f "$cfg" ]] || [[ ! -s "$cfg" ]] && return
    # 用两阶段提取：先找 server 名字，再在后续行找 command
    awk '
    /"mcpServers"/ { in_mcp=1; next }
    in_mcp && !in_server {
      # 匹配 "serverName": {
      if ($0 ~ /"[a-zA-Z0-9_-]+".*\{/) {
        # 提取引号内的名字
        n=split($0, parts, "\"")
        for (i=1; i<=n; i++) {
          if (parts[i] ~ /^[a-zA-Z0-9_-]+$/ && parts[i] != "mcpServers" && parts[i] != "command" && parts[i] != "args") {
            name=parts[i]
            break
          }
        }
        if (name != "") in_server=1
        next
      }
    }
    in_server && /"command"/ {
      # 提取 command 值
      gsub(/.*"command"[[:space:]]*:[[:space:]]*"/, "")
      gsub(/".*/, "")
      if (name != "" && $0 != "") print name "|" $0
      in_server=0
      name=""
      next
    }
    in_server && /\}[[:space:]]*$/ { in_server=0; name="" }
    ' "$cfg" 2>/dev/null
  }

  local sp mcp_file
  sp="$(_owd_settings_path)"
  mcp_file="$HOME/.claude/.mcp.json"
  local server_list=""

  for cfg in "$sp" "$mcp_file" "$PWD/.mcp.json"; do
    [[ -z "$cfg" || ! -f "$cfg" ]] && continue
    while IFS='|' read -r sname scmd; do
      [[ -z "$sname" || -z "$scmd" ]] && continue
      mcp_count=$((mcp_count + 1))
      server_list+="$sname|$scmd"$'\n'
    done < <(_owd_extract_mcp_servers "$cfg")
  done

  if (( mcp_count == 0 )); then
    _OWD_STATUS="warn"
    _OWD_SCORE=2
    _OWD_SUMMARY="No MCP servers configured"
    _OWD_DETAIL="  ⚠️  No MCP servers found in any config\n"
    return
  fi

  # 验证每个 server 的 command
  while IFS='|' read -r sname scmd; do
    [[ -z "$sname" || -z "$scmd" ]] && continue
    local runner
    runner="$(echo "$scmd" | awk '{print $1}')"
    if _owd_has_cmd "$runner" || [[ -x "$runner" ]]; then
      _OWD_DETAIL+="  ✅ $sname ($scmd)\n"
    else
      _OWD_DETAIL+="  ❌ $sname: $runner not found\n"
      unreachable=$((unreachable + 1))
    fi
  done <<< "$server_list"

  if (( unreachable == 0 )); then
    _OWD_STATUS="pass"
    _OWD_SCORE=$_OWD_MAX
    _OWD_SUMMARY="$mcp_count configured, all reachable"
  else
    _OWD_STATUS="warn"
    _OWD_SCORE=$(( _OWD_MAX / 2 ))
    _OWD_SUMMARY="$mcp_count configured, $unreachable unreachable"
  fi
}

# 4. 权限配置 (5分)
owd_check_permissions() {
  _OWD_MAX=5
  local sp
  sp="$(_owd_settings_path)"
  _OWD_DETAIL=""

  if [[ -z "$sp" ]]; then
    _OWD_STATUS="warn"
    _OWD_SCORE=3
    _OWD_SUMMARY="No settings.json (default permissions)"
    return
  fi

  # 实际字段是 permissions.defaultMode
  local mode
  mode="$(_owd_json_value "$sp" "defaultMode")"
  local allowed_count
  allowed_count="$(grep -c '"allow"' "$sp" 2>/dev/null || echo 0)"

  # 检查 bypassPermissions（旧字段名兼容）
  if [[ "$mode" == "bypassPermissions" ]] || grep -q '"bypassPermissions"' "$sp" 2>/dev/null; then
    _OWD_STATUS="warn"
    _OWD_SCORE=2
    _OWD_SUMMARY="Bypass mode — security risk"
    _OWD_DETAIL="  ⚠️  bypassPermissions enabled\n"
    _OWD_DETAIL+="  ⚠️  Consider using plan or auto mode\n"
  elif [[ -n "$mode" ]]; then
    _OWD_STATUS="pass"
    _OWD_SCORE=$_OWD_MAX
    _OWD_SUMMARY="Mode: $mode, $allowed_count allowed tool(s)"
    _OWD_DETAIL+="  ✅ Mode: $mode\n"
    _OWD_DETAIL+="  ✅ $allowed_count allowed tool(s)\n"
  else
    _OWD_STATUS="warn"
    _OWD_SCORE=3
    _OWD_SUMMARY="Default permissions (interactive prompts)"
    _OWD_DETAIL+="  ℹ️  No explicit permission mode set\n"
  fi
}

# 5. Hooks 配置 (8分) — 提取实际 command 并验证
owd_check_hooks() {
  _OWD_MAX=8
  local sp
  sp="$(_owd_settings_path)"
  _OWD_DETAIL=""

  if [[ -z "$sp" ]]; then
    _OWD_STATUS="warn"
    _OWD_SCORE=4
    _OWD_SUMMARY="No settings.json (cannot check hooks)"
    return
  fi

  local hook_types="PreToolUse PostToolUse Stop"
  local found_types=0 total_hooks=0 broken=0
  local has_pre=false has_post=false has_stop=false

  for ht in $hook_types; do
    if grep -q "\"$ht\"" "$sp" 2>/dev/null; then
      found_types=$((found_types + 1))
      case "$ht" in
        PreToolUse) has_pre=true ;;
        PostToolUse) has_post=true ;;
        Stop) has_stop=true ;;
      esac

      # 提取该类型下所有 command 值
      local ht_cmds
      ht_cmds="$(awk "/\"$ht\"/,/\\]/" "$sp" | grep '"command"' | grep -v '"type".*"command"' | sed 's/.*"command"[[:space:]]*:[[:space:]]*"//' | sed 's/".*//' 2>/dev/null)"
      local ht_count=0
      while IFS= read -r cmd; do
        [[ -z "$cmd" ]] && continue
        ht_count=$((ht_count + 1))
        total_hooks=$((total_hooks + 1))

        # 验证 command 可执行性
        local runner
        runner="$(echo "$cmd" | awk '{print $1}')"
        local rest_args
        rest_args="$(echo "$cmd" | awk '{$1=""; print $0}' | sed 's/^ *//')"
        local script_path=""

        # 提取脚本路径（找第一个 .sh 或绝对路径参数）
        script_path="$(echo "$rest_args" | awk '{for(i=1;i<=NF;i++) if($i ~ /\// || $i ~ /\.sh$/) {print $i; break}}')"

        if [[ "$runner" == "npx" || "$runner" == "node" || "$runner" == "python3" || "$runner" == "python" || "$runner" == "bash" || "$runner" == "/bin/bash" || "$runner" == "sh" || "$runner" == "/bin/sh" || "$runner" == "bun" ]]; then
          # 脚本类 hook：检查 runner 和脚本文件
          if _owd_has_cmd "$runner"; then
            if [[ -n "$script_path" ]] && [[ "$script_path" == /* ]]; then
              if [[ -f "$script_path" ]]; then
                _OWD_DETAIL+="  ✅ $ht: $runner $(basename "$script_path")\n"
              else
                _OWD_DETAIL+="  ❌ $ht: $script_path not found\n"
                broken=$((broken + 1))
              fi
            else
              _OWD_DETAIL+="  ✅ $ht: $runner (inline)\n"
            fi
          else
            _OWD_DETAIL+="  ❌ $ht: $runner not in PATH\n"
            broken=$((broken + 1))
          fi
        elif [[ "$runner" == /* ]]; then
          # 绝对路径命令
          if [[ -x "$runner" ]]; then
            _OWD_DETAIL+="  ✅ $ht: $runner\n"
          else
            _OWD_DETAIL+="  ❌ $ht: $runner not executable\n"
            broken=$((broken + 1))
          fi
        else
          # 其他命令（如 pnpm, npm）
          if _owd_has_cmd "$runner"; then
            _OWD_DETAIL+="  ✅ $ht: $cmd\n"
          else
            _OWD_DETAIL+="  ❌ $ht: $runner not found\n"
            broken=$((broken + 1))
          fi
        fi
      done < <(echo "$ht_cmds")

      if (( ht_count == 0 )); then
        _OWD_DETAIL+="  ⚠️  $ht: type exists but no commands\n"
      fi
    else
      _OWD_DETAIL+="  ⚠️  No $ht hooks\n"
    fi
  done

  # 覆盖度评分：PreToolUse + PostToolUse + Stop 各占权重
  local coverage=0
  $has_pre  && coverage=$((coverage + 1))
  $has_post && coverage=$((coverage + 1))
  $has_stop && coverage=$((coverage + 1))

  if (( broken > 0 )); then
    _OWD_STATUS="warn"
    _OWD_SCORE=$(( _OWD_MAX / 2 ))
    _OWD_SUMMARY="$total_hooks hook(s), $broken broken"
  elif (( coverage >= 2 )); then
    _OWD_STATUS="pass"
    _OWD_SCORE=$_OWD_MAX
    _OWD_SUMMARY="$found_types types, $total_hooks hook(s) active"
  elif (( coverage >= 1 )); then
    _OWD_STATUS="warn"
    _OWD_SCORE=$(( _OWD_MAX * 3 / 4 ))
    _OWD_SUMMARY="$found_types type(s), $total_hooks hook(s)"
    _OWD_DETAIL+="  💡 Consider adding PreToolUse hooks for safety\n"
  else
    _OWD_STATUS="fail"
    _OWD_SCORE=0
    _OWD_SUMMARY="No hooks configured"
    _OWD_DETAIL+="  💡 Hooks automate safety checks and formatting\n"
    _OWD_DETAIL+="  💡 Recommended: PreToolUse (format), PostToolUse (lint), Stop (audit)\n"
  fi
}

# 6. Skills (5分) — 检查数量、SKILL.md 完整性、token 开销
owd_check_skills() {
  _OWD_MAX=5
  _OWD_DETAIL=""

  local skill_dir="$HOME/.claude/skills"
  local skill_count=0 total_tokens=0 missing_readme=0 heavy_skills=0

  if [[ ! -d "$skill_dir" ]]; then
    _OWD_STATUS="fail"
    _OWD_SCORE=0
    _OWD_SUMMARY="No skills directory"
    _OWD_DETAIL="  ❌ $skill_dir not found\n"
    return
  fi

  for d in "$skill_dir"/*/; do
    [[ -d "$d" ]] || continue
    skill_count=$((skill_count + 1))
    local name
    name="$(basename "$d")"
    if _owd_has_file "$d/SKILL.md"; then
      local tk
      tk="$(_owd_estimate_tokens "$d/SKILL.md")"
      total_tokens=$((total_tokens + tk))
      if (( tk > 5000 )); then
        heavy_skills=$((heavy_skills + 1))
      fi
    else
      missing_readme=$((missing_readme + 1))
    fi
  done

  # 摘要行
  _OWD_DETAIL+="  ℹ️  $skill_count skills (~${total_tokens}t total)\n"
  if (( heavy_skills > 0 )); then
    _OWD_DETAIL+="  ⚠️  $heavy_skills heavy skill(s) (>5000t each)\n"
  fi
  if (( missing_readme > 0 )); then
    _OWD_DETAIL+="  ⚠️  $missing_readme missing SKILL.md\n"
  fi

  if (( skill_count == 0 )); then
    _OWD_STATUS="warn"
    _OWD_SCORE=1
    _OWD_SUMMARY="No skills installed"
  elif (( missing_readme > 0 )); then
    _OWD_STATUS="warn"
    _OWD_SCORE=3
    _OWD_SUMMARY="$skill_count skills, $missing_readme missing SKILL.md"
  else
    _OWD_STATUS="pass"
    _OWD_SCORE=$_OWD_MAX
    _OWD_SUMMARY="$skill_count skills (~${total_tokens}t)"
  fi
}

# 7. Agents (5分) — 检查数量、关键 agent 覆盖、内容有效性
owd_check_agents() {
  _OWD_MAX=5
  _OWD_DETAIL=""

  local agent_dir="$HOME/.claude/agents"
  local agent_count=0 empty_agents=0 total_tokens=0

  if [[ ! -d "$agent_dir" ]]; then
    _OWD_STATUS="warn"
    _OWD_SCORE=2
    _OWD_SUMMARY="No agents directory"
    _OWD_DETAIL="  ⚠️  $agent_dir not found\n"
    return
  fi

  for f in "$agent_dir"/*.md; do
    [[ -f "$f" ]] || continue
    agent_count=$((agent_count + 1))
    local name
    name="$(basename "$f" .md)"
    local lines
    lines="$(wc -l < "$f" | tr -d ' ')"
    local tk
    tk="$(_owd_estimate_tokens "$f")"
    total_tokens=$((total_tokens + tk))
    if (( lines < 5 )); then
      empty_agents=$((empty_agents + 1))
    fi
  done

  # 关键 agent 覆盖
  local key="planner architect tdd-guide code-reviewer security-reviewer build-error-resolver"
  local key_found=0
  for k in $key; do
    [[ -f "$agent_dir/$k.md" ]] && key_found=$((key_found + 1))
  done

  _OWD_DETAIL+="  ℹ️  $agent_count agents (~${total_tokens}t), $key_found/7 key agents\n"
  if (( empty_agents > 0 )); then
    _OWD_DETAIL+="  ⚠️  $empty_agents agent(s) with <5 lines (stub)\n"
  fi

  if (( agent_count == 0 )); then
    _OWD_STATUS="warn"
    _OWD_SCORE=2
    _OWD_SUMMARY="No agent definitions"
  elif (( key_found >= 4 && empty_agents == 0 )); then
    _OWD_STATUS="pass"
    _OWD_SCORE=$_OWD_MAX
    _OWD_SUMMARY="$agent_count agents, $key_found key agents"
  elif (( agent_count >= 3 )); then
    _OWD_STATUS="warn"
    _OWD_SCORE=$(( _OWD_MAX / 2 ))
    _OWD_SUMMARY="$agent_count agents, $key_found key agents, $empty_agents empty"
  else
    _OWD_STATUS="warn"
    _OWD_SCORE=2
    _OWD_SUMMARY="$agent_count agents (sparse)"
  fi
}

# 8. Rules (6分)
owd_check_rules() {
  _OWD_MAX=6
  _OWD_DETAIL=""

  local rules_dir="$HOME/.claude/rules"
  if [[ ! -d "$rules_dir" ]]; then
    _OWD_STATUS="fail"
    _OWD_SCORE=0
    _OWD_SUMMARY="No rules directory"
    _OWD_DETAIL="  ❌ $rules_dir not found\n"
    return
  fi

  # 检查 common 目录
  local common_files=0
  if [[ -d "$rules_dir/common" ]]; then
    for f in "$rules_dir/common"/*.md; do
      [[ -f "$f" ]] && common_files=$((common_files + 1))
    done
  fi

  # 检查语言目录
  local lang_dirs=0
  for d in "$rules_dir"/*/; do
    local dn
    dn="$(basename "$d")"
    [[ "$dn" == "common" || "$dn" == "zh" ]] && continue
    [[ -f "$d/${dn}.md" ]] || [[ -n "$(ls "$d"/*.md 2>/dev/null)" ]] && lang_dirs=$((lang_dirs + 1))
  done

  _OWD_DETAIL+="  ✅ common/: $common_files file(s)\n"
  if (( lang_dirs > 0 )); then
    _OWD_DETAIL+="  ✅ $lang_dirs language-specific rule set(s)\n"
  else
    _OWD_DETAIL+="  ℹ️  No language-specific rules\n"
  fi

  if (( common_files >= 5 )); then
    _OWD_STATUS="pass"
    _OWD_SCORE=$_OWD_MAX
    _OWD_SUMMARY="common: $common_files files, $lang_dirs lang sets"
  elif (( common_files >= 1 )); then
    _OWD_STATUS="warn"
    _OWD_SCORE=3
    _OWD_SUMMARY="common: $common_files files (incomplete)"
  else
    _OWD_STATUS="fail"
    _OWD_SCORE=0
    _OWD_SUMMARY="No common rules"
  fi
}

# 9. Memory 系统 (5分) — 检查内容质量，薄的文件不加分
owd_check_memory() {
  _OWD_MAX=5
  _OWD_DETAIL=""
  local quality=0

  # 全局 CLAUDE.md（>=10 行才算有意义）
  local gcm="$HOME/.claude/CLAUDE.md"
  if _owd_has_file "$gcm"; then
    local lines
    lines="$(wc -l < "$gcm" | tr -d ' ')"
    if (( lines >= 10 )); then
      quality=$((quality + 1))
      _OWD_DETAIL+="  ✅ Global CLAUDE.md: ${lines} lines\n"
    elif (( lines >= 3 )); then
      _OWD_DETAIL+="  ⚠️  Global CLAUDE.md thin (${lines} lines, need >=10)\n"
    else
      _OWD_DETAIL+="  ❌ Global CLAUDE.md too thin (${lines} lines)\n"
    fi
  else
    _OWD_DETAIL+="  ❌ No global CLAUDE.md\n"
  fi

  # 项目级 memory 目录
  local thin_files=0
  if [[ -n "${PWD:-}" ]]; then
    local pmem="$PWD/memory"
    if [[ -d "$pmem" ]]; then
      local mfiles
      mfiles="$(ls "$pmem"/*.md 2>/dev/null | wc -l | tr -d ' ')"
      if (( mfiles >= 3 )); then
        quality=$((quality + 1))
        _OWD_DETAIL+="  ✅ memory/: $mfiles files\n"
      elif (( mfiles >= 1 )); then
        _OWD_DETAIL+="  ⚠️  memory/: only $mfiles file(s) (need >=3)\n"
      else
        _OWD_DETAIL+="  ❌ memory/ exists but empty\n"
      fi

      # 检查关键文件内容质量（<5 行算薄，不加分并扣分）
      for mf in decisions.md lessons.md updates.md; do
        if _owd_has_file "$pmem/$mf"; then
          local mflines
          mflines="$(wc -l < "$pmem/$mf" | tr -d ' ')"
          if (( mflines >= 10 )); then
            quality=$((quality + 1))
            _OWD_DETAIL+="  ✅ $mf: ${mflines} lines (rich)\n"
          elif (( mflines >= 5 )); then
            quality=$((quality + 1))
            _OWD_DETAIL+="  ✅ $mf: ${mflines} lines\n"
          else
            thin_files=$((thin_files + 1))
            _OWD_DETAIL+="  ⚠️  $mf: only ${mflines} lines (needs content)\n"
          fi
        else
          _OWD_DETAIL+="  ❌ $mf not found\n"
        fi
      done
    else
      _OWD_DETAIL+="  ❌ No project memory/ directory\n"
    fi

    # 检查 updates.md 活跃度
    if _owd_has_file "$pmem/updates.md"; then
      local updated_ago
      updated_ago="$(find "$pmem/updates.md" -mtime -7 2>/dev/null)"
      if [[ -n "$updated_ago" ]]; then
        quality=$((quality + 1))
        _OWD_DETAIL+="  ✅ updates.md active (updated within 7 days)\n"
      else
        _OWD_DETAIL+="  ⚠️  updates.md stale (7+ days since update)\n"
      fi
    fi
  fi

  # 薄文件扣分
  local adjusted=$(( quality - thin_files ))
  (( adjusted < 0 )) && adjusted=0

  if (( adjusted >= 4 )); then
    _OWD_STATUS="pass"
    _OWD_SCORE=$_OWD_MAX
    _OWD_SUMMARY="Memory rich and actively maintained"
  elif (( adjusted >= 2 )); then
    _OWD_STATUS="warn"
    _OWD_SCORE=$(( _OWD_MAX / 2 ))
    _OWD_SUMMARY="Memory exists but ${thin_files} file(s) too thin"
  elif (( adjusted >= 1 )); then
    _OWD_STATUS="warn"
    _OWD_SCORE=1
    _OWD_SUMMARY="Memory mostly empty templates"
  else
    _OWD_STATUS="fail"
    _OWD_SCORE=0
    _OWD_SUMMARY="No meaningful memory content"
  fi
}

# 10. 项目上下文 (7分) — 检查内容质量，不仅是文件存在
owd_check_project_context() {
  _OWD_MAX=7
  _OWD_DETAIL=""
  local quality=0

  # 检查核心文件内容质量
  local core_files="CLAUDE.md:10 CONTEXT.md:5 STATE.md:3 TODO.md:3"
  for entry in $core_files; do
    local f="${entry%%:*}"
    local min_lines="${entry##*:}"
    if _owd_has_file "$PWD/$f"; then
      local lines
      lines="$(wc -l < "$PWD/$f" | tr -d ' ')"
      if (( lines >= min_lines )); then
        quality=$((quality + 1))
        _OWD_DETAIL+="  ✅ $f: ${lines} lines (meaningful)\n"
      else
        _OWD_DETAIL+="  ⚠️  $f: only ${lines} lines (needs content)\n"
      fi
    else
      _OWD_DETAIL+="  ❌ $f missing\n"
    fi
  done

  # AGENTS.md 可选
  if _owd_has_file "$PWD/AGENTS.md"; then
    quality=$((quality + 1))
    _OWD_DETAIL+="  ✅ AGENTS.md present\n"
  else
    _OWD_DETAIL+="  ℹ️  AGENTS.md (optional, recommended for teams)\n"
  fi

  # PROJECT_CONTEXT.md 跨会话 handoff
  if _owd_has_file "$PWD/PROJECT_CONTEXT.md"; then
    local pclines
    pclines="$(wc -l < "$PWD/PROJECT_CONTEXT.md" | tr -d ' ')"
    if (( pclines >= 5 )); then
      quality=$((quality + 1))
      _OWD_DETAIL+="  ✅ PROJECT_CONTEXT.md: ${pclines} lines (handoff ready)\n"
    else
      _OWD_DETAIL+="  ⚠️  PROJECT_CONTEXT.md too thin\n"
    fi
  else
    _OWD_DETAIL+="  ⚠️  No PROJECT_CONTEXT.md (no cross-session handoff)\n"
  fi

  if (( quality >= 5 )); then
    _OWD_STATUS="pass"
    _OWD_SCORE=$_OWD_MAX
    _OWD_SUMMARY="Project context rich and well-structured"
  elif (( quality >= 3 )); then
    _OWD_STATUS="warn"
    _OWD_SCORE=$(( _OWD_MAX / 2 ))
    _OWD_SUMMARY="Some context files present but quality gaps"
  else
    _OWD_STATUS="fail"
    _OWD_SCORE=1
    _OWD_SUMMARY="Project lacks structured context"
  fi
}

# 11. 上下文卫生 (6分) — 增加 CLAUDE.md 大小检查
owd_check_context_hygiene() {
  _OWD_MAX=6
  _OWD_DETAIL=""

  local has_cignore=false large_files=0 noise=0

  # CLAUDE.md 大小检查（过大浪费 context）
  local project_cm="$PWD/CLAUDE.md"
  if _owd_has_file "$project_cm"; then
    local cm_lines
    cm_lines="$(wc -l < "$project_cm" | tr -d ' ')"
    local cm_tokens
    cm_tokens="$(_owd_estimate_tokens "$project_cm")"
    if (( cm_lines > 200 )); then
      noise=$((noise + 1))
      _OWD_DETAIL+="  ⚠️  CLAUDE.md: ${cm_lines} lines (~${cm_tokens}t) — too large, trim to <200 lines\n"
    elif (( cm_lines > 100 )); then
      _OWD_DETAIL+="  ⚠️  CLAUDE.md: ${cm_lines} lines (~${cm_tokens}t) — consider trimming\n"
    else
      _OWD_DETAIL+="  ✅ CLAUDE.md: ${cm_lines} lines (~${cm_tokens}t) — lean\n"
    fi
  fi

  # 全局 CLAUDE.md 大小
  local gcm="$HOME/.claude/CLAUDE.md"
  if _owd_has_file "$gcm" ; then
    local gcm_tokens
    gcm_tokens="$(_owd_estimate_tokens "$gcm")"
    if (( gcm_tokens > 2000 )); then
      noise=$((noise + 1))
      _OWD_DETAIL+="  ⚠️  Global CLAUDE.md: ~${gcm_tokens}t — heavy overhead\n"
    else
      _OWD_DETAIL+="  ✅ Global CLAUDE.md: ~${gcm_tokens}t\n"
    fi
  fi

  if _owd_has_file "$PWD/.claudeignore"; then
    has_cignore=true
    _OWD_DETAIL+="  ✅ .claudeignore present\n"
  else
    _OWD_DETAIL+="  ⚠️  No .claudeignore — context may include noise\n"
  fi

  # 计算项目文件数和大文件
  if [[ -d "$PWD" ]]; then
    local total_files
    total_files="$(find "$PWD" -maxdepth 3 -type f \
      ! -path '*/node_modules/*' ! -path '*/.git/*' ! -path '*/.claude/*' \
      2>/dev/null | wc -l | tr -d ' ')"

    _OWD_DETAIL+="  ℹ️  $total_files files (depth 3)\n"

    # 检查大文件（>100KB 非 .git）
    large_files="$(find "$PWD" -maxdepth 3 -type f -size +100k \
      ! -path '*/node_modules/*' ! -path '*/.git/*' \
      2>/dev/null | wc -l | tr -d ' ')"
    if (( large_files > 5 )); then
      _OWD_DETAIL+="  ⚠️  $large_files large files (>100KB)\n"
      noise=$((noise + 1))
    else
      _OWD_DETAIL+="  ✅ $large_files large files\n"
    fi

    # 检查常见噪音源
    for nd in "dist" "build" ".next" "coverage" ".cache"; do
      if [[ -d "$PWD/$nd" ]]; then
        noise=$((noise + 1))
        _OWD_DETAIL+="  ⚠️  $nd/ present (should be in .claudeignore)\n"
      fi
    done
  fi

  if $has_cignore && (( noise == 0 )); then
    _OWD_STATUS="pass"
    _OWD_SCORE=$_OWD_MAX
    _OWD_SUMMARY="Clean context, all files lean"
  elif $has_cignore || (( noise <= 1 )); then
    _OWD_STATUS="warn"
    _OWD_SCORE=3
    _OWD_SUMMARY="$noise noise/bloat source(s)"
  else
    _OWD_STATUS="fail"
    _OWD_SCORE=1
    _OWD_SUMMARY="$noise noise/bloat sources, no .claudeignore"
  fi
}

# 12. Git 配置 (5分)
owd_check_git() {
  _OWD_MAX=5
  _OWD_DETAIL=""

  if ! _owd_has_cmd git; then
    _OWD_STATUS="fail"
    _OWD_SCORE=0
    _OWD_SUMMARY="git not installed"
    _OWD_DETAIL="  ❌ git not found\n"
    return
  fi

  local issues=0

  # 检查 git config
  local gname gemail
  gname="$(git config user.name 2>/dev/null || true)"
  gemail="$(git config user.email 2>/dev/null || true)"

  if [[ -n "$gname" ]]; then
    _OWD_DETAIL+="  ✅ user.name: $gname\n"
  else
    _OWD_DETAIL+="  ❌ user.name not set\n"
    issues=$((issues + 1))
  fi

  if [[ -n "$gemail" ]]; then
    _OWD_DETAIL+="  ✅ user.email: $gemail\n"
  else
    _OWD_DETAIL+="  ❌ user.email not set\n"
    issues=$((issues + 1))
  fi

  # 检查 .gitignore
  if _owd_has_file "$PWD/.gitignore"; then
    local gi_essentials="node_modules .env .claude"
    local gi_missing=0
    for e in $gi_essentials; do
      grep -q "$e" "$PWD/.gitignore" 2>/dev/null || gi_missing=$((gi_missing + 1))
    done
    if (( gi_missing == 0 )); then
      _OWD_DETAIL+="  ✅ .gitignore covers essentials\n"
    else
      _OWD_DETAIL+="  ⚠️  .gitignore missing $gi_missing essential entries\n"
      issues=$((issues + 1))
    fi
  else
    _OWD_DETAIL+="  ⚠️  No .gitignore file\n"
    issues=$((issues + 1))
  fi

  if (( issues == 0 )); then
    _OWD_STATUS="pass"
    _OWD_SCORE=$_OWD_MAX
    _OWD_SUMMARY="git properly configured"
  else
    _OWD_STATUS="warn"
    _OWD_SCORE=$(( _OWD_MAX / 2 ))
    _OWD_SUMMARY="$issues git issue(s)"
  fi
}

# 13. 终端环境 (5分) — 有区分度的检查
owd_check_terminal() {
  _OWD_MAX=5
  _OWD_DETAIL=""
  local quality=0

  local shell_name
  shell_name="$(basename "${SHELL:-unknown}")"
  _OWD_DETAIL+="  ✅ Shell: $shell_name\n"
  quality=$((quality + 1))

  # PATH 检查
  if [[ ":$PATH:" == *":$HOME/.local/bin:"* ]]; then
    _OWD_DETAIL+="  ✅ ~/.local/bin in PATH\n"
    quality=$((quality + 1))
  else
    _OWD_DETAIL+="  ⚠️  ~/.local/bin not in PATH\n"
  fi

  # tmux
  if _owd_has_cmd tmux; then
    _OWD_DETAIL+="  ✅ tmux available\n"
    quality=$((quality + 1))
  else
    _OWD_DETAIL+="  ⚠️  tmux not installed (recommended for long tasks)\n"
  fi

  # COLOR 支持（影响脚本输出可读性）
  local term="${TERM:-unknown}"
  if [[ "$term" == *"-256color" ]] || [[ "$term" == "xterm-kitty" ]] || [[ "$term" == "screen-256color" ]]; then
    _OWD_DETAIL+="  ✅ 256-color: $term\n"
    quality=$((quality + 1))
  elif [[ "$term" == *"-color" ]]; then
    _OWD_DETAIL+="  ℹ️  Color: $term (basic)\n"
  else
    _OWD_DETAIL+="  ⚠️  TERM=$term (limited color support)\n"
  fi

  # EDITOR 环境变量
  if [[ -n "${EDITOR:-}" ]]; then
    _OWD_DETAIL+="  ✅ EDITOR: $EDITOR\n"
  else
    _OWD_DETAIL+="  ℹ️  No EDITOR set\n"
  fi

  if (( quality >= 4 )); then
    _OWD_STATUS="pass"
    _OWD_SCORE=$_OWD_MAX
    _OWD_SUMMARY="Shell: $shell_name, tmux: $(_owd_has_cmd tmux && echo yes || echo no), 256-color"
  elif (( quality >= 2 )); then
    _OWD_STATUS="pass"
    _OWD_SCORE=$(( _OWD_MAX * 4 / 5 ))
    _OWD_SUMMARY="Shell: $shell_name, tmux: $(_owd_has_cmd tmux && echo yes || echo no)"
  else
    _OWD_STATUS="warn"
    _OWD_SCORE=$(( _OWD_MAX / 2 ))
    _OWD_SUMMARY="Shell: $shell_name, limited terminal setup"
  fi
}

# 14. 安全检查 (10分)
owd_check_security() {
  _OWD_MAX=10
  _OWD_DETAIL=""
  local issues=0

  # .env 在 .gitignore?
  if [[ -f "$PWD/.gitignore" ]]; then
    if grep -q '\.env' "$PWD/.gitignore" 2>/dev/null; then
      _OWD_DETAIL+="  ✅ .env in .gitignore\n"
    else
      _OWD_DETAIL+="  ❌ .env NOT in .gitignore\n"
      issues=$((issues + 2))
    fi
  fi

  # .env 文件存在但权限检查
  if [[ -f "$PWD/.env" ]]; then
    local perms
    perms="$(stat -f '%Lp' "$PWD/.env" 2>/dev/null || stat -c '%a' "$PWD/.env" 2>/dev/null || echo "644")"
    if [[ "${perms: -1}" -le 4 ]]; then
      _OWD_DETAIL+="  ✅ .env permissions: $perms\n"
    else
      _OWD_DETAIL+="  ⚠️  .env permissions: $perms (should be 600)\n"
      issues=$((issues + 1))
    fi
  fi

  # 硬编码密钥扫描（逐模式搜索，不依赖 brace expansion）
  local key_found=0
  if [[ -d "$PWD" ]]; then
    local scan_ext="-name '*.sh' -o -name '*.js' -o -name '*.ts' -o -name '*.py' -o -name '*.go' -o -name '*.rs' -o -name '*.yaml' -o -name '*.yml' -o -name '*.toml' -o -name '*.env' -o -name '*.conf' -o -name '*.json'"
    # 简化：用 grep -r 逐 pattern 搜索
    local p1 p2 p3
    p1="$(grep -rl 'sk-[a-zA-Z0-9]\{20,\}' "$PWD" --include='*.sh' --include='*.js' --include='*.ts' --include='*.py' --include='*.env' --include='*.yaml' --include='*.yml' --include='*.json' --exclude-dir='.git' --exclude-dir='node_modules' --exclude-dir='vendor' 2>/dev/null | head -3)"
    p2="$(grep -rl 'ghp_[a-zA-Z0-9]\{36,\}' "$PWD" --include='*.sh' --include='*.js' --include='*.ts' --include='*.py' --include='*.env' --include='*.yaml' --include='*.yml' --include='*.json' --exclude-dir='.git' --exclude-dir='node_modules' --exclude-dir='vendor' 2>/dev/null | head -3)"
    p3="$(grep -rl 'xox[bpsa]-[a-zA-Z0-9-]\{10,\}' "$PWD" --include='*.sh' --include='*.js' --include='*.ts' --include='*.py' --include='*.env' --include='*.yaml' --include='*.yml' --include='*.json' --exclude-dir='.git' --exclude-dir='node_modules' --exclude-dir='vendor' 2>/dev/null | head -3)"
    [[ -n "$p1" ]] && key_found=$((key_found + 1))
    [[ -n "$p2" ]] && key_found=$((key_found + 1))
    [[ -n "$p3" ]] && key_found=$((key_found + 1))
  fi

  if (( key_found > 0 )); then
    _OWD_DETAIL+="  ❌ Potential hardcoded secrets detected ($key_found patterns)\n"
    issues=$((issues + 3))
  else
    _OWD_DETAIL+="  ✅ No obvious hardcoded secrets\n"
  fi

  # .claude/settings.json 权限
  local sp="$HOME/.claude/settings.json"
  if [[ -f "$sp" ]]; then
    local sp_perms
    sp_perms="$(stat -f '%Lp' "$sp" 2>/dev/null || stat -c '%a' "$sp" 2>/dev/null || echo "644")"
    if [[ "${sp_perms: -1}" -le 6 ]]; then
      _OWD_DETAIL+="  ✅ settings.json permissions: $sp_perms\n"
    else
      _OWD_DETAIL+="  ⚠️  settings.json permissions: $sp_perms (world-readable)\n"
      issues=$((issues + 1))
    fi
  fi

  # 检查 bypassPermissions
  if [[ -f "$sp" ]] && grep -q '"bypassPermissions"' "$sp" 2>/dev/null; then
    _OWD_DETAIL+="  ❌ bypassPermissions enabled — all safety guards off\n"
    issues=$((issues + 3))
  fi

  if (( issues == 0 )); then
    _OWD_STATUS="pass"
    _OWD_SCORE=$_OWD_MAX
    _OWD_SUMMARY="No security issues detected"
  elif (( issues <= 2 )); then
    _OWD_STATUS="warn"
    _OWD_SCORE=$(( _OWD_MAX / 2 ))
    _OWD_SUMMARY="$issues minor issue(s)"
  else
    _OWD_STATUS="fail"
    _OWD_SCORE=0
    _OWD_SUMMARY="$issues security issue(s) found"
  fi
}

# 15. 成本效率 (8分)
owd_check_cost_efficiency() {
  _OWD_MAX=8
  _OWD_DETAIL=""

  local total_tokens=0

  # Skills tokens
  for f in "$HOME/.claude/skills"/*/SKILL.md; do
    [[ -f "$f" ]] || continue
    total_tokens=$((total_tokens + $(_owd_estimate_tokens "$f")))
  done

  # Agents tokens
  for f in "$HOME/.claude/agents"/*.md; do
    [[ -f "$f" ]] || continue
    total_tokens=$((total_tokens + $(_owd_estimate_tokens "$f")))
  done

  # Rules tokens
  for f in "$HOME/.claude/rules"/*.md "$HOME/.claude/rules"/**/*.md; do
    [[ -f "$f" ]] || continue
    total_tokens=$((total_tokens + $(_owd_estimate_tokens "$f")))
  done

  # Global CLAUDE.md
  if _owd_has_file "$HOME/.claude/CLAUDE.md"; then
    total_tokens=$((total_tokens + $(_owd_estimate_tokens "$HOME/.claude/CLAUDE.md")))
  fi

  _OWD_DETAIL+="  ℹ️  Total context overhead: ~${total_tokens} tokens\n"

  if (( total_tokens < 20000 )); then
    _OWD_STATUS="pass"
    _OWD_SCORE=$_OWD_MAX
    _OWD_SUMMARY="~${total_tokens}t overhead — lean setup"
  elif (( total_tokens < 50000 )); then
    _OWD_STATUS="pass"
    _OWD_SCORE=$(( _OWD_MAX * 3 / 4 ))
    _OWD_SUMMARY="~${total_tokens}t overhead — moderate"
  elif (( total_tokens < 100000 )); then
    _OWD_STATUS="warn"
    _OWD_SCORE=$(( _OWD_MAX / 2 ))
    _OWD_SUMMARY="~${total_tokens}t overhead — consider pruning"
  else
    _OWD_STATUS="fail"
    _OWD_SCORE=$(( _OWD_MAX / 4 ))
    _OWD_SUMMARY="~${total_tokens}t overhead — heavy, review skills/rules"
  fi
  _OWD_DETAIL+="  ℹ️  (rules + skills + agents + global CLAUDE.md)\n"
}

# 16. 开发流程 (8分) — 传统 + AI 开发实践
owd_check_workflow() {
  _OWD_MAX=12
  _OWD_DETAIL=""
  local quality=0
  local total_checks=10

  # ─── 1. 规划流程 (Plan) ───
  local plan_score=0

  # 1a. CLAUDE.md 是否提及 plan/规划流程
  local plan_mentioned=false
  if _owd_has_file "$PWD/CLAUDE.md"; then
    if grep -qiE 'plan|规划|先.*计划|任务.*路由|步骤|先.*给.*计划' "$PWD/CLAUDE.md" 2>/dev/null; then
      plan_mentioned=true
    fi
  fi
  if $plan_mentioned; then
    plan_score=$((plan_score + 1))
    _OWD_DETAIL+="  ✅ Plan flow: CLAUDE.md defines planning process\n"
  else
    _OWD_DETAIL+="  ⚠️  Plan flow: CLAUDE.md missing planning instructions\n"
  fi

  # 1b. planner agent 存在
  if _owd_has_file "$HOME/.claude/agents/planner.md"; then
    plan_score=$((plan_score + 1))
  fi

  # 1c. development-workflow.md 规则（定义完整开发流程）
  local dev_workflow=false
  if [[ -f "$HOME/.claude/rules/development-workflow.md" ]] || \
     [[ -f "$HOME/.claude/rules/common/development-workflow.md" ]]; then
    dev_workflow=true
    plan_score=$((plan_score + 1))
  fi

  if (( plan_score >= 3 )); then
    quality=$((quality + 1))
    _OWD_DETAIL+="  ✅ Planning: planner agent + workflow rule + CLAUDE.md\n"
  elif (( plan_score >= 2 )); then
    _OWD_DETAIL+="  ℹ️  Planning: $plan_score/3 (partial plan flow)\n"
  else
    _OWD_DETAIL+="  ⚠️  Planning: no structured plan flow detected\n"
  fi

  # ─── 2. 任务管理闭环 (Task / TODO) ───
  local task_score=0
  local pm_files="TODO.md STATE.md"
  local pm_rich=0
  for pf in $pm_files; do
    if _owd_has_file "$PWD/$pf"; then
      local pfl
      pfl="$(wc -l < "$PWD/$pf" | tr -d ' ')"
      if (( pfl >= 5 )); then
        pm_rich=$((pm_rich + 1))
        _OWD_DETAIL+="  ✅ $pf: ${pfl} lines (active tracking)\n"
      elif (( pfl >= 2 )); then
        pm_rich=$((pm_rich + 1))
        _OWD_DETAIL+="  ⚠️  $pf: ${pfl} lines (thin but present)\n"
      else
        _OWD_DETAIL+="  ⚠️  $pf: ${pfl} lines (stub)\n"
      fi
    fi
  done
  if (( pm_rich >= 2 )); then
    task_score=2
  elif (( pm_rich >= 1 )); then
    task_score=1
  fi

  # 2b. 任务是否近期活跃（7天内有修改）
  if _owd_has_file "$PWD/TODO.md"; then
    local todo_age
    todo_age="$(find "$PWD/TODO.md" -mtime -7 2>/dev/null)"
    if [[ -n "$todo_age" ]]; then
      task_score=$((task_score + 1))
      _OWD_DETAIL+="  ✅ TODO.md updated within 7 days\n"
    else
      _OWD_DETAIL+="  ⚠️  TODO.md stale (>7 days since update)\n"
    fi
  fi

  if (( task_score >= 2 )); then
    quality=$((quality + 1))
  else
    _OWD_DETAIL+="  ⚠️  Task tracking: no active TODO/STATE management\n"
  fi

  # ─── 3. TDD / 测试闭环 ───
  local tdd_score=0

  # 3a. 测试框架
  local found_test=false
  if [[ -d "$PWD/tests" ]] || [[ -d "$PWD/test" ]] || [[ -d "$PWD/__tests__" ]] || \
     [[ -d "$PWD/src/__tests__" ]] || [[ -f "$PWD/pytest.ini" ]] || \
     [[ -f "$PWD/jest.config"* ]] || [[ -f "$PWD/vitest.config"* ]] || \
     { [[ -f "$PWD/package.json" ]] && grep -q '"test"' "$PWD/package.json" 2>/dev/null; }; then
    found_test=true
    tdd_score=$((tdd_score + 1))
    _OWD_DETAIL+="  ✅ Test framework detected\n"
  else
    _OWD_DETAIL+="  ⚠️  No test framework found\n"
  fi

  # 3b. tdd-guide agent（写测试的习惯）
  if _owd_has_file "$HOME/.claude/agents/tdd-guide.md"; then
    tdd_score=$((tdd_score + 1))
  fi

  # 3c. testing 规则
  if [[ -f "$HOME/.claude/rules/testing.md" ]] || \
     [[ -f "$HOME/.claude/rules/common/testing.md" ]]; then
    tdd_score=$((tdd_score + 1))
  fi

  if $found_test && (( tdd_score >= 2 )); then
    quality=$((quality + 1))
    _OWD_DETAIL+="  ✅ TDD loop: test framework + tdd agent/rule\n"
  elif $found_test; then
    quality=$((quality + 1))
    _OWD_DETAIL+="  ℹ️  TDD loop: test framework only, no tdd agent/rule\n"
  elif (( tdd_score >= 1 )); then
    _OWD_DETAIL+="  ⚠️  TDD loop: tdd agent/rule but no test framework\n"
  else
    _OWD_DETAIL+="  ⚠️  TDD loop: no test infrastructure\n"
  fi

  # ─── 4. Code Review 流程 ───
  local review_score=0

  # 4a. code-reviewer agent
  if _owd_has_file "$HOME/.claude/agents/code-reviewer.md"; then
    review_score=$((review_score + 1))
  fi

  # 4b. code-review 规则
  if [[ -f "$HOME/.claude/rules/code-review.md" ]] || \
     [[ -f "$HOME/.claude/rules/common/code-review.md" ]]; then
    review_score=$((review_score + 1))
  fi

  # 4c. security-reviewer agent
  if _owd_has_file "$HOME/.claude/agents/security-reviewer.md"; then
    review_score=$((review_score + 1))
  fi

  if (( review_score >= 2 )); then
    quality=$((quality + 1))
    _OWD_DETAIL+="  ✅ Review flow: reviewer agent + review rule ($review_score/3)\n"
  elif (( review_score >= 1 )); then
    _OWD_DETAIL+="  ℹ️  Review flow: partial ($review_score/3)\n"
  else
    _OWD_DETAIL+="  ⚠️  Review flow: no code review infrastructure\n"
  fi

  # ─── 5. 质量门禁 (Hooks) ───
  local sp
  sp="$(_owd_settings_path)"
  local gate_score=0

  if [[ -n "$sp" ]]; then
    # 5a. PreToolUse hooks（pre-commit 级别的检查）
    if grep -q '"PreToolUse"' "$sp" 2>/dev/null; then
      gate_score=$((gate_score + 1))
      _OWD_DETAIL+="  ✅ PreToolUse hooks: pre-execution validation\n"
    else
      _OWD_DETAIL+="  ⚠️  No PreToolUse hooks — no pre-execution gates\n"
    fi

    # 5b. PostToolUse hooks（自动 format/lint）
    if grep -q '"PostToolUse"' "$sp" 2>/dev/null; then
      gate_score=$((gate_score + 1))
      _OWD_DETAIL+="  ✅ PostToolUse hooks: auto-format/lint\n"
    else
      _OWD_DETAIL+="  ⚠️  No PostToolUse hooks — no auto-format on save\n"
    fi

    # 5c. Stop hooks（会话结束检查）
    if grep -q '"Stop"' "$sp" 2>/dev/null; then
      gate_score=$((gate_score + 1))
    fi
  else
    _OWD_DETAIL+="  ⚠️  No settings.json — cannot check hooks\n"
  fi

  if (( gate_score >= 2 )); then
    quality=$((quality + 1))
  fi

  # ─── 6. 文档 & Handoff（跨会话交接） ───
  local handoff_score=0
  local handoff_files="AGENTS.md CONTEXT.md PROJECT_CONTEXT.md"
  local handoff_rich=0
  for hf in $handoff_files; do
    if _owd_has_file "$PWD/$hf"; then
      local hfl
      hfl="$(wc -l < "$PWD/$hf" | tr -d ' ')"
      if (( hfl >= 5 )); then
        handoff_rich=$((handoff_rich + 1))
      fi
    fi
  done
  if (( handoff_rich >= 2 )); then
    handoff_score=2
    _OWD_DETAIL+="  ✅ Handoff: $handoff_rich/3 context files (AGENTS/CONTEXT/PROJECT)\n"
  elif (( handoff_rich >= 1 )); then
    handoff_score=1
    _OWD_DETAIL+="  ℹ️  Handoff: $handoff_rich/3 context files\n"
  else
    _OWD_DETAIL+="  ⚠️  Handoff: no context files for cross-session continuity\n"
  fi

  if [[ -d "$PWD/docs" ]]; then
    handoff_score=$((handoff_score + 1))
  fi

  if (( handoff_score >= 2 )); then
    quality=$((quality + 1))
  fi

  # ─── 7. Memory 学习闭环 ───
  local mem_score=0
  if [[ -d "$PWD/memory" ]]; then
    local mem_files="updates.md decisions.md lessons.md"
    local mem_rich=0
    for mf in $mem_files; do
      if _owd_has_file "$PWD/memory/$mf"; then
        local mfl
        mfl="$(wc -l < "$PWD/memory/$mf" | tr -d ' ')"
        if (( mfl >= 5 )); then
          mem_rich=$((mem_rich + 1))
        fi
      fi
    done
    if (( mem_rich >= 2 )); then
      mem_score=2
      _OWD_DETAIL+="  ✅ Memory loop: $mem_rich/3 rich memory files\n"
    elif (( mem_rich >= 1 )); then
      mem_score=1
      _OWD_DETAIL+="  ℹ️  Memory loop: $mem_rich/3 memory files (some thin)\n"
    else
      _OWD_DETAIL+="  ⚠️  Memory loop: memory/ exists but files are thin\n"
    fi

    # 7b. memory 是否近期更新
    local mem_recent
    mem_recent="$(find "$PWD/memory" -name "*.md" -mtime -7 2>/dev/null | head -1)"
    if [[ -n "$mem_recent" ]]; then
      mem_score=$((mem_score + 1))
      _OWD_DETAIL+="  ✅ Memory: updated within 7 days\n"
    fi
  else
    _OWD_DETAIL+="  ⚠️  No memory/ directory — no learning loop\n"
  fi

  if (( mem_score >= 2 )); then
    quality=$((quality + 1))
  fi

  # ─── 8. Git 规范 ───
  local git_score=0
  if _owd_has_cmd git && [[ -d "$PWD/.git" ]]; then
    # 8a. Conventional commits
    local recent_commits
    recent_commits="$(git -C "$PWD" log --oneline -20 2>/dev/null | grep -cE '^[a-f0-9]+ (feat|fix|refactor|docs|test|chore|perf|ci):' || echo 0)"
    if (( recent_commits >= 5 )); then
      git_score=$((git_score + 1))
      _OWD_DETAIL+="  ✅ Conventional commits: $recent_commits/20 recent\n"
    elif (( recent_commits >= 1 )); then
      _OWD_DETAIL+="  ℹ️  Commits: $recent_commits/20 conventional (inconsistent)\n"
    else
      _OWD_DETAIL+="  ⚠️  No conventional commits detected\n"
    fi

    # 8b. git-workflow 规则
    if [[ -f "$HOME/.claude/rules/git-workflow.md" ]] || \
       [[ -f "$HOME/.claude/rules/common/git-workflow.md" ]]; then
      git_score=$((git_score + 1))
    fi

    # 8c. Lock file（可复现构建）
    if [[ -f "$PWD/package-lock.json" ]] || [[ -f "$PWD/yarn.lock" ]] || \
       [[ -f "$PWD/pnpm-lock.yaml" ]] || [[ -f "$PWD/poetry.lock" ]] || \
       [[ -f "$PWD/Cargo.lock" ]] || [[ -f "$PWD/go.sum" ]] || \
       [[ -f "$PWD/bun.lockb" ]]; then
      git_score=$((git_score + 1))
      _OWD_DETAIL+="  ✅ Lock file: reproducible builds\n"
    else
      _OWD_DETAIL+="  ⚠️  No lock file\n"
    fi
  else
    _OWD_DETAIL+="  ℹ️  Not a git repo — skipping git checks\n"
  fi

  if (( git_score >= 2 )); then
    quality=$((quality + 1))
  fi

  # ─── 9. Rules 体系（编码规范） ───
  local common_count=0
  if [[ -d "$HOME/.claude/rules/common" ]]; then
    common_count="$(ls "$HOME/.claude/rules/common"/*.md 2>/dev/null | wc -l | tr -d ' ')"
  fi
  if (( common_count >= 5 )); then
    quality=$((quality + 1))
    _OWD_DETAIL+="  ✅ Rules: $common_count common rules (disciplined)\n"
  elif (( common_count >= 2 )); then
    _OWD_DETAIL+="  ℹ️  Rules: $common_count common rules (partial)\n"
  else
    _OWD_DETAIL+="  ⚠️  Rules: no common rules — no coding standards\n"
  fi

  # ─── 10. Agent 体系（分工合理） ───
  local agent_dir="$HOME/.claude/agents"
  local key_agents="planner tdd-guide code-reviewer architect"
  local agents_found=0
  for ag in $key_agents; do
    if _owd_has_file "$agent_dir/$ag.md"; then
      agents_found=$((agents_found + 1))
    fi
  done
  if (( agents_found >= 3 )); then
    quality=$((quality + 1))
    _OWD_DETAIL+="  ✅ Key agents: $agents_found/4 (plan/tdd/review/arch)\n"
  elif (( agents_found >= 1 )); then
    _OWD_DETAIL+="  ℹ️  Key agents: $agents_found/4 (partial coverage)\n"
  else
    _OWD_DETAIL+="  ⚠️  No key dev agents configured\n"
  fi

  # ─── 计分 ───
  if (( quality >= 8 )); then
    _OWD_STATUS="pass"
    _OWD_SCORE=$_OWD_MAX
    _OWD_SUMMARY="Dev flow mature ($quality/$total_checks indicators)"
  elif (( quality >= 6 )); then
    _OWD_STATUS="warn"
    _OWD_SCORE=$(( _OWD_MAX * 3 / 4 ))
    _OWD_SUMMARY="Dev flow good ($quality/$total_checks indicators)"
  elif (( quality >= 4 )); then
    _OWD_STATUS="warn"
    _OWD_SCORE=$(( _OWD_MAX / 2 ))
    _OWD_SUMMARY="Dev flow partial ($quality/$total_checks indicators)"
  elif (( quality >= 2 )); then
    _OWD_STATUS="warn"
    _OWD_SCORE=$(( _OWD_MAX / 3 ))
    _OWD_SUMMARY="Dev flow gaps ($quality/$total_checks indicators)"
  else
    _OWD_STATUS="fail"
    _OWD_SCORE=$(( _OWD_MAX / 4 ))
    _OWD_SUMMARY="Dev flow immature ($quality/$total_checks indicators)"
  fi
}

# ─── 检查执行 ───

_OWD_CHECK_FUNCS=(
  owd_check_tools
  owd_check_model_config
  owd_check_mcp_servers
  owd_check_permissions
  owd_check_hooks
  owd_check_skills
  owd_check_agents
  owd_check_rules
  owd_check_memory
  owd_check_project_context
  owd_check_context_hygiene
  owd_check_git
  owd_check_terminal
  owd_check_security
  owd_check_cost_efficiency
  owd_check_workflow
)

owd_run_all_checks() {
  OWD_RESULTS=()
  OWD_DETAILS=()
  OWD_TOTAL_SCORE=0

  for func in "${_OWD_CHECK_FUNCS[@]}"; do
    "$func"
    OWD_RESULTS+=("$func|$_OWD_STATUS|$_OWD_SCORE|$_OWD_MAX|$_OWD_SUMMARY")
    OWD_DETAILS+=("$func|$_OWD_DETAIL")
    OWD_TOTAL_SCORE=$((OWD_TOTAL_SCORE + _OWD_SCORE))
  done
}

# ─── 颜色与可视化辅助 ───

# ANSI 颜色
readonly _OWD_C_RESET='\033[0m'
readonly _OWD_C_BOLD='\033[1m'
readonly _OWD_C_DIM='\033[2m'
readonly _OWD_C_GREEN='\033[32m'
readonly _OWD_C_YELLOW='\033[33m'
readonly _OWD_C_RED='\033[31m'
readonly _OWD_C_CYAN='\033[36m'
readonly _OWD_C_WHITE='\033[37m'
readonly _OWD_C_BGREEN='\033[1;32m'
readonly _OWD_C_BYELLOW='\033[1;33m'
readonly _OWD_C_BRED='\033[1;31m'

# 分数进度条（10 格宽）
_owd_score_bar() {
  local score="$1" max="$2"
  local pct=$(( score * 100 / max ))
  local filled=$(( pct / 10 ))
  local empty=$(( 10 - filled ))

  local bar=""
  local i
  if (( pct >= 80 )); then
    for (( i=0; i<filled; i++ )); do bar+="█"; done
    for (( i=0; i<empty; i++ )); do bar+="░"; done
    printf "${_OWD_C_GREEN}%s${_OWD_C_RESET}" "$bar"
  elif (( pct >= 40 )); then
    for (( i=0; i<filled; i++ )); do bar+="█"; done
    for (( i=0; i<empty; i++ )); do bar+="░"; done
    printf "${_OWD_C_YELLOW}%s${_OWD_C_RESET}" "$bar"
  else
    for (( i=0; i<filled; i++ )); do bar+="█"; done
    for (( i=0; i<empty; i++ )); do bar+="░"; done
    printf "${_OWD_C_RED}%s${_OWD_C_RESET}" "$bar"
  fi
}

# 总分进度条（20 格宽）
_owd_total_bar() {
  local score="$1" max="$2"
  local pct=$(( score * 100 / max ))
  local filled=$(( pct / 5 ))
  local empty=$(( 20 - filled ))

  local bar=""
  local i
  if (( pct >= 80 )); then
    for (( i=0; i<filled; i++ )); do bar+="█"; done
    for (( i=0; i<empty; i++ )); do bar+="░"; done
    printf "${_OWD_C_BGREEN}%s${_OWD_C_RESET}" "$bar"
  elif (( pct >= 50 )); then
    for (( i=0; i<filled; i++ )); do bar+="█"; done
    for (( i=0; i<empty; i++ )); do bar+="░"; done
    printf "${_OWD_C_BYELLOW}%s${_OWD_C_RESET}" "$bar"
  else
    for (( i=0; i<filled; i++ )); do bar+="█"; done
    for (( i=0; i<empty; i++ )); do bar+="░"; done
    printf "${_OWD_C_BRED}%s${_OWD_C_RESET}" "$bar"
  fi
}

# 状态颜色标签
_owd_status_tag() {
  local status="$1"
  case "$status" in
    pass) printf "${_OWD_C_BGREEN} PASS ${_OWD_C_RESET}" ;;
    warn) printf "${_OWD_C_BYELLOW} WARN ${_OWD_C_RESET}" ;;
    fail) printf "${_OWD_C_BRED} FAIL ${_OWD_C_RESET}" ;;
  esac
}

# 友好维度名
_owd_label() {
  local func="$1"
  echo "$func" | sed 's/owd_check_//' | sed 's/_/ /g' | awk '{for(i=1;i<=NF;i++)$i=toupper(substr($i,1,1))tolower(substr($i,2))}1'
}

# ─── 报告函数 ───

owd_report_summary() {
  local pass=0 warn=0 fail=0
  for r in "${OWD_RESULTS[@]}"; do
    local st
    st="$(echo "$r" | cut -d'|' -f2)"
    case "$st" in
      pass) pass=$((pass + 1)) ;;
      warn) warn=$((warn + 1)) ;;
      fail) fail=$((fail + 1)) ;;
    esac
  done

  local pct=$(( OWD_TOTAL_SCORE * 100 / OWD_TOTAL_MAX ))

  echo ""
  echo -e "  ${_OWD_C_BOLD}Overall Score${_OWD_C_RESET}"
  echo -e "  $(_owd_total_bar "$OWD_TOTAL_SCORE" "$OWD_TOTAL_MAX")  ${_OWD_C_BOLD}${OWD_TOTAL_SCORE}${_OWD_C_RESET}/${OWD_TOTAL_MAX} (${pct}%)"
  echo ""
  echo -e "  ${_OWD_C_GREEN}● ${pass} passed${_OWD_C_RESET}    ${_OWD_C_YELLOW}● ${warn} warnings${_OWD_C_RESET}    ${_OWD_C_RED}● ${fail} critical${_OWD_C_RESET}"
  echo ""

  # 分组：先显示 fail，再 warn，最后 pass
  echo -e "  ${_OWD_C_DIM}─────────────────────────────────────────────────${_OWD_C_RESET}"

  # 失败项
  if (( fail > 0 )); then
    for r in "${OWD_RESULTS[@]}"; do
      IFS='|' read -r func status score max summary <<< "$r"
      [[ "$status" != "fail" ]] && continue
      local label
      label="$(_owd_label "$func")"
      echo -e "  $(_owd_status_tag "$status") $(_owd_score_bar "$score" "$max") ${_OWD_C_BOLD}${label}${_OWD_C_RESET}  ${_OWD_C_DIM}${score}/${max}${_OWD_C_RESET}"
      echo -e "         ${_OWD_C_RED}${summary}${_OWD_C_RESET}"
    done
  fi

  # 告警项
  if (( warn > 0 )); then
    for r in "${OWD_RESULTS[@]}"; do
      IFS='|' read -r func status score max summary <<< "$r"
      [[ "$status" != "warn" ]] && continue
      local label
      label="$(_owd_label "$func")"
      echo -e "  $(_owd_status_tag "$status") $(_owd_score_bar "$score" "$max") ${_OWD_C_BOLD}${label}${_OWD_C_RESET}  ${_OWD_C_DIM}${score}/${max}${_OWD_C_RESET}"
      echo -e "         ${_OWD_C_YELLOW}${summary}${_OWD_C_RESET}"
    done
  fi

  # 通过项
  if (( pass > 0 )); then
    for r in "${OWD_RESULTS[@]}"; do
      IFS='|' read -r func status score max summary <<< "$r"
      [[ "$status" != "pass" ]] && continue
      local label
      label="$(_owd_label "$func")"
      echo -e "  $(_owd_status_tag "$status") $(_owd_score_bar "$score" "$max") ${label}  ${_OWD_C_DIM}${score}/${max}${_OWD_C_RESET}"
    done
  fi

  echo -e "  ${_OWD_C_DIM}─────────────────────────────────────────────────${_OWD_C_RESET}"
}

owd_report_detail() {
  local pct=$(( OWD_TOTAL_SCORE * 100 / OWD_TOTAL_MAX ))

  echo ""
  echo -e "  ${_OWD_C_BOLD}Overall Score${_OWD_C_RESET}"
  echo -e "  $(_owd_total_bar "$OWD_TOTAL_SCORE" "$OWD_TOTAL_MAX")  ${_OWD_C_BOLD}${OWD_TOTAL_SCORE}${_OWD_C_RESET}/${OWD_TOTAL_MAX} (${pct}%)"
  echo -e "  ${_OWD_C_DIM}═════════════════════════════════════════════════${_OWD_C_RESET}"

  for i in "${!OWD_RESULTS[@]}"; do
    local r="${OWD_RESULTS[$i]}"
    local d="${OWD_DETAILS[$i]}"
    IFS='|' read -r func status score max summary <<< "$r"
    local label
    label="$(_owd_label "$func")"

    local status_color=""
    case "$status" in
      pass) status_color="$_OWD_C_GREEN" ;;
      warn) status_color="$_OWD_C_YELLOW" ;;
      fail) status_color="$_OWD_C_RED" ;;
    esac

    echo ""
    echo -e "  $(_owd_status_tag "$status") $(_owd_score_bar "$score" "$max") ${_OWD_C_BOLD}${label}${_OWD_C_RESET}  ${_OWD_C_DIM}${score}/${max}${_OWD_C_RESET}"
    echo -e "         ${status_color}${summary}${_OWD_C_RESET}"

    # 输出 detail 子项（去掉 func_name| 前缀）
    echo "$d" | cut -d'|' -f2- | while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      # 替换 emoji 为带颜色的文本
      line="$(echo "$line" | sed "s/✅/${_OWD_C_GREEN}  ✓${_OWD_C_RESET}/g")"
      line="$(echo "$line" | sed "s/⚠️ /${_OWD_C_YELLOW}  ⚠${_OWD_C_RESET}/g")"
      line="$(echo "$line" | sed "s/❌/${_OWD_C_RED}  ✗${_OWD_C_RESET}/g")"
      line="$(echo "$line" | sed "s/ℹ️ /${_OWD_C_CYAN}  ℹ${_OWD_C_RESET}/g")"
      echo -e "    $line"
    done
  done

  echo ""
  echo -e "  ${_OWD_C_DIM}═════════════════════════════════════════════════${_OWD_C_RESET}"
}

owd_report_json() {
  echo "{"
  echo "  \"timestamp\": \"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\","
  echo "  \"os\": \"$(ow_detect_os)\","
  echo "  \"score\": $OWD_TOTAL_SCORE,"
  echo "  \"max\": $OWD_TOTAL_MAX,"
  echo "  \"checks\": ["

  local first=true
  for i in "${!OWD_RESULTS[@]}"; do
    local r="${OWD_RESULTS[$i]}"
    IFS='|' read -r func status score max summary <<< "$r"
    local label
    label="$(echo "$func" | sed 's/owd_check_//' | sed 's/_/ /g')"

    $first || echo ","
    first=false
    printf '    {"name": "%s", "status": "%s", "score": %d, "max": %d, "summary": "%s"}' \
      "$label" "$status" "$score" "$max" "$summary"
  done

  echo ""
  echo "  ]"
  echo "}"
}

owd_report_combined() {
  echo ""
  echo -e "  ${_OWD_C_BOLD}owlwatch health + doctor${_OWD_C_RESET}  ${_OWD_C_DIM}$(date '+%Y-%m-%d %H:%M') | $(ow_detect_os)${_OWD_C_RESET}"
  echo -e "  ${_OWD_C_DIM}═════════════════════════════════════════════════${_OWD_C_RESET}"

  # 运行 health report（如果 lib 可用）
  if type ow_top_cpu &>/dev/null; then
    echo ""
    echo -e "  ${_OWD_C_BOLD}── System Health ──${_OWD_C_RESET}"
    source "$ROOT_DIR/lib/process.sh" 2>/dev/null || true
    source "$ROOT_DIR/lib/memory.sh" 2>/dev/null || true

    local mem_info
    mem_info="$(ow_memory_summary 2>/dev/null || echo '?|?|?|?|?|?')"
    IFS='|' read -r mem_total mem_used mem_avail mem_pct _ _ <<< "$mem_info"
    echo -e "  Memory: ${mem_pct:-?}% used"

    local load_info
    load_info="$(ow_load_average 2>/dev/null || echo '?|?|?|?')"
    IFS='|' read -r load1 _ _ cores <<< "$load_info"
    echo -e "  Load: ${load1:-?} (${cores:-?} cores)"
  fi

  echo ""
  echo -e "  ${_OWD_C_BOLD}── Dev Environment Check ──${_OWD_C_RESET}"
  owd_report_summary
}
