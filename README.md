# owlwatch

macOS / Linux system performance monitor for Claude Code.

One command to check system health, detect orphan processes, analyze Chrome, and clean up — directly from your Claude Code session or terminal.

## Features

- **System Health Report** — CPU top, memory top, disk, swap, load average, with threshold alerts
- **Orphan Process Detection** — finds background processes with no terminal, high CPU, long runtime
- **Process Tree View** — shows PID/PPID relationship for codex/claude/node processes
- **Process Cleanup** — safely kill orphans (SIGTERM → SIGKILL), protected system processes never touched
- **Kill by Name** — `--name codex` kills all matching processes
- **Chrome Analysis** — memory breakdown by tabs/extensions/GPU, installed extension list
- **Daemon Mode** — macOS launchd auto-cleanup on interval (optional)
- **Cross-Platform** — macOS + Linux, auto-detects OS
- **Zero Dependencies** — pure bash 3.2+, only uses ps/awk/sysctl

## Quick Start

### Install as Claude Code Skill

```bash
git clone https://github.com/your-username/owlwatch.git
cd owlwatch
bash install.sh
```

Then in Claude Code:

```
/owlwatch
```

### Install Standalone (without Claude Code)

```bash
bash install.sh --standalone
```

### Uninstall

```bash
bash uninstall.sh          # Remove Claude Code skill
bash uninstall.sh --all    # Remove everything
```

## Commands

| Command | Description |
|---------|-------------|
| `owlwatch-health.sh` | Full system health report |
| `owlwatch-health.sh --json` | JSON output for scripts |
| `owlwatch-clean.sh` | Scan orphan processes (dry run) |
| `owlwatch-clean.sh --yes` | Auto-clean all detected orphans |
| `owlwatch-clean.sh --pid 12345` | Kill specific PID |
| `owlwatch-clean.sh --name codex` | Kill all processes by name |
| `owlwatch-chrome.sh` | Chrome memory and extension analysis |
| `owlwatch-daemon.sh install` | Install background auto-cleanup (macOS) |
| `owlwatch-daemon.sh status` | Check daemon status |
| `owlwatch-daemon.sh uninstall` | Remove daemon |

## Configuration

Config file: `conf/owlwatch.conf`

```bash
# Thresholds
CPU_WARN_THRESHOLD=70        # CPU alert %
MEM_WARN_THRESHOLD=80        # Memory alert %
DISK_WARN_THRESHOLD=85       # Disk alert %

# Orphan detection
ORPHAN_CPU_THRESHOLD=50      # Min CPU% to count as orphan
ORPHAN_MIN_RUNTIME=30        # Min runtime in minutes
ORPHAN_PATTERNS="codex claude-mem-codex-watcher"

# Protected processes (never killed)
PROTECT_NAMES="kernel_task WindowServer loginwindow launchd syslogd"

# Daemon interval
DAEMON_INTERVAL=1800         # 30 minutes
```

Override with environment variables using `OW_` prefix:

```bash
export OW_CPU_WARN_THRESHOLD=90
export OW_ORPHAN_PATTERNS="codex node python"
```

## Architecture

```
owlwatch/
├── bin/
│   ├── owlwatch-health.sh     # Health report entry
│   ├── owlwatch-clean.sh      # Process cleanup entry
│   ├── owlwatch-chrome.sh     # Chrome analysis entry
│   └── owlwatch-daemon.sh     # Daemon management entry
├── lib/
│   ├── common.sh              # Config, logging, formatting, OS detection
│   ├── process.sh             # Process analysis, orphan detection, process tree
│   ├── memory.sh              # Memory, disk, load average
│   └── chrome.sh              # Chrome extensions and memory
├── conf/
│   ├── owlwatch.conf.example  # Example config
│   └── owlwatch.conf          # Active config (created on install)
├── install.sh                 # Installer
├── uninstall.sh               # Uninstaller
├── SKILL.md                   # Claude Code skill registration
└── LICENSE                    # MIT
```

## Stop Hook (Optional)

Auto-run health check when Claude Code session ends:

```json
{
  "hooks": {
    "Stop": [
      {
        "command": "bash $HOME/.claude/skills/owlwatch/bin/owlwatch-health.sh",
        "description": "System health report on session end"
      }
    ]
  }
}
```

## Requirements

- bash 3.2+
- macOS or Linux
- No external dependencies (no python, node, jq required)

## License

MIT
