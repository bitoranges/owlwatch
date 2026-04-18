# /owlwatch — 专业系统性能监控

## 触发
用户说 "/owlwatch"、"检查系统"、"系统健康"、"风扇吵"、"电脑卡"、"杀进程"、"清理进程"、"Chrome 分析"、"内存分析"、"进程监控" 等。

## 脚本位置
所有脚本在 `~/.claude/skills/owlwatch/bin/` 下（安装后）。

## 命令路由

| 用户意图 | 执行命令 | 说明 |
|----------|----------|------|
| 系统健康/检查系统 | `bash ~/.claude/skills/owlwatch/bin/owlwatch-health.sh` | 完整健康报告 |
| 清理进程/杀进程 | `bash ~/.claude/skills/owlwatch/bin/owlwatch-clean.sh` | 仅检测，不杀 |
| 确认清理 | `bash ~/.claude/skills/owlwatch/bin/owlwatch-clean.sh --yes` | 执行清理 |
| 杀指定 PID | `bash ~/.claude/skills/owlwatch/bin/owlwatch-clean.sh --pid <PID>` | 杀单个进程 |
| Chrome 分析 | `bash ~/.claude/skills/owlwatch/bin/owlwatch-chrome.sh` | Chrome 报告 |
| 安装 daemon | `bash ~/.claude/skills/owlwatch/bin/owlwatch-daemon.sh install` | 后台自动清理 |
| 卸载 daemon | `bash ~/.claude/skills/owlwatch/bin/owlwatch-daemon.sh uninstall` | 停止后台清理 |
| daemon 状态 | `bash ~/.claude/skills/owlwatch/bin/owlwatch-daemon.sh status` | 查看状态 |

## 执行流程

### 1. 健康检查（默认）
运行 `owlwatch-health.sh`，获得完整报告。

### 2. 解读报告
- 用简体中文向用户总结关键发现
- 优先说明告警项（⚠️ 和 🔴）
- 解释孤儿进程的含义和风险

### 3. 建议操作
- 列出可以安全杀掉的孤儿进程及 PID
- 询问用户是否执行清理
- 用户确认后使用 `owlwatch-clean.sh --yes` 或 `--pid` 执行

### 4. 验证清理结果
清理后再次运行 `owlwatch-health.sh` 确认效果。

## 输出规则
- 始终使用简体中文
- 报告包含：CPU Top、内存 Top、系统资源、孤儿进程
- 使用 emoji 标记状态：✅ 正常、⚠️ 告警、🔴 严重
- 数值使用人类可读格式（GB、MB、%）

## 安全规则
- 只建议杀孤儿进程（无终端 + 高 CPU + 长时间运行）
- 永远不杀 kernel_task、WindowServer、loginwindow 等系统进程（PROTECT_NAMES）
- 永远不杀有终端绑定的活跃会话
- 执行 kill 前必须获得用户明确确认
- 不自动安装 daemon，需用户显式请求

## 配置
配置文件：`~/.claude/skills/owlwatch/conf/owlwatch.conf`
- 无配置文件时使用内置默认值
- 环境变量覆盖：加 `OW_` 前缀，如 `OW_CPU_WARN_THRESHOLD=90`

## Stop Hook（可选）
在 `~/.claude/settings.json` 中配置，会话结束时自动检查：
```json
{
  "hooks": {
    "Stop": [
      {
        "command": "bash $HOME/.claude/skills/owlwatch/bin/owlwatch-health.sh",
        "description": "会话结束时输出系统健康报告"
      }
    ]
  }
}
```

## 与旧 cleanup skill 的关系
owlwatch 完全替代 `~/.claude/skills/cleanup/`。两者可共存不冲突，但建议优先使用 owlwatch。
