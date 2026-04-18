#!/bin/bash
# chrome.sh — owlwatch Chrome 分析函数
# 依赖：common.sh（ow_init 必须已调用）
# 纯 bash/awk 实现，不依赖 python3

# ─── Chrome 扩展清单 ───
# 输出格式：EXT_ID|NAME|VERSION
ow_chrome_extensions() {
  local os
  os="$(ow_detect_os)"
  local ext_dir

  if [[ "$os" == "macos" ]]; then
    ext_dir="$HOME/Library/Application Support/Google/Chrome/Default/Extensions"
  else
    ext_dir="$HOME/.config/google-chrome/Default/Extensions"
  fi

  if [[ ! -d "$ext_dir" ]]; then
    echo "INFO: Chrome 扩展目录不存在（Chrome 未安装或使用其他 profile）"
    return 0
  fi

  local ext_id version_dir manifest name version
  for ext_id in "$ext_dir"/*/; do
    [[ -d "$ext_id" ]] || continue
    ext_id="$(basename "$ext_id")"

    version_dir="$(find "$ext_dir/$ext_id" -maxdepth 1 -type d -exec basename {} \; | sort -V | tail -1)"
    manifest="$ext_dir/$ext_id/$version_dir/manifest.json"

    if [[ -f "$manifest" ]]; then
      name="$(_ow_json_extract "$manifest" "name")"
      version="$(_ow_json_extract "$manifest" "version")"
      printf "%s|%s|%s\n" "$ext_id" "${name:-Unknown}" "${version:-?}"
    fi
  done
}

# 从 JSON 文件提取指定 key 的字符串值（纯 awk）
_ow_json_extract() {
  local file="$1" key="$2"
  awk -v k="\"$key\"" '
  {
    idx = index($0, k)
    if (idx == 0) next
    rest = substr($0, idx + length(k))
    gsub(/^[ \t]*:[ \t]*"/, "", rest)
    gsub(/".*/, "", rest)
    print rest
    exit
  }' "$file"
}

# ─── Chrome 内存分析 ───
# 使用 ps -eo 可靠格式，避免 ps aux 字段偏移
# 输出格式：total|renderers|gpu|extensions_count|tab_estimate
ow_chrome_memory() {
  local total
  total="$(ps -eo rss=%rss,comm=%comm -m 2>/dev/null | awk '$2 == "Google" {sum += $1} END {printf "%.0f", sum/1024}')"

  local renderers renderer_mem
  renderers="$(ps -eo rss=%rss,args= 2>/dev/null | awk '/--type=renderer/ {cnt++} END {print cnt+0}')"
  renderer_mem="$(ps -eo rss=%rss,args= 2>/dev/null | awk '/--type=renderer/ {sum += $1} END {printf "%.0f", sum/1024}')"

  local gpu_mem
  gpu_mem="$(ps -eo rss=%rss,args= 2>/dev/null | awk '/--type=gpu-process/ {sum += $1} END {printf "%.0f", sum/1024}')"

  local ext_renderers
  ext_renderers="$(ps -eo args= 2>/dev/null | awk '/--type=renderer.*--extension-process/ {cnt++} END {print cnt+0}')"

  local tab_estimate=$(( renderers - ext_renderers ))
  (( tab_estimate < 0 )) && tab_estimate=0

  printf "%s|%s|%s|%s|%s\n" "${total:-0}" "${renderer_mem:-0}" "${gpu_mem:-0}" "$ext_renderers" "$tab_estimate"
}
