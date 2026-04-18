# owlwatch

macOS / Linux system performance monitor — works in terminal, Claude Code, Cursor, Windsurf, or any AI agent.

One command to check system health, detect orphan processes, analyze Chrome, and clean up.

## Features

- **System Health Report** — CPU, memory, disk, load average, with threshold alerts
- **Orphan Process Detection** — finds background processes with no terminal, high CPU, long runtime
- **Process Tree View** — shows PID/PPID relationship
- **Process Cleanup** — safely kill orphans (SIGTERM → SIGKILL), protected system processes never touched
- **Kill by Name** — `--name codex` kills all matching processes
- **Chrome Analysis** — memory breakdown by tabs/extensions/GPU, installed extension list
- **Daemon Mode** — macOS launchd auto-cleanup on interval (optional)
- **Cross-Platform** — macOS + Linux, auto-detects OS
- **Zero Dependencies** — pure bash 3.2+, only uses ps/awk/sysctl
- **AI Agent Support** — adapters for Claude Code, Cursor, Windsurf

## Quick Start

### Install CLI (default)

```bash
git clone https://github.com/bitoranges/owlwatch.git
cd owlwatch
bash install.sh
```

Run:

```bash
owlwatch health
```

### Install with AI integration

```bash
bash install.sh --claude         # Also install as Claude Code skill
bash install.sh --cursor         # Print Cursor rules setup instructions
bash install.sh --windsurf       # Print Windsurf rules setup instructions
bash install.sh --claude --cursor --windsurf  # All of the above
```

### Uninstall

```bash
bash install.sh --uninstall
```

## Commands

```
owlwatch                        # Full health report (default)
owlwatch health                 # Same as above
owlwatch health --json          # JSON output for scripts
owlwatch clean                  # Scan orphan processes (dry run)
owlwatch clean --yes            # Auto-clean all detected orphans
owlwatch clean --pid 12345      # Kill specific PID
owlwatch clean --name codex     # Kill all processes by name
owlwatch chrome                 # Chrome memory and extension analysis
owlwatch daemon install         # Install background auto-cleanup (macOS)
owlwatch daemon status          # Check daemon status
owlwatch daemon uninstall       # Remove daemon
```

## Configuration

Config file: `~/.local/share/owlwatch/conf/owlwatch.conf`

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

## AI Agent Integration

owlwatch ships adapter files for popular AI coding tools. The installer handles setup automatically.

### Claude Code

```bash
bash install.sh --claude
```

Then use `/owlwatch` in Claude Code, or say "check system", "system health", "clean processes", etc.

### Cursor

```bash
bash install.sh --cursor
# Then follow the printed instructions to copy rules
```

### Windsurf

```bash
bash install.sh --windsurf
# Then follow the printed instructions to append rules
```

### Other AI agents

owlwatch is a plain CLI tool — any agent that can run shell commands can use it. Just run `owlwatch health` and parse the output.

## Architecture

```
owlwatch/
├── bin/
│   ├── owlwatch                # Unified CLI entry point
│   ├── owlwatch-health.sh      # Health report
│   ├── owlwatch-clean.sh       # Process cleanup
│   ├── owlwatch-chrome.sh      # Chrome analysis
│   └── owlwatch-daemon.sh      # Daemon management
├── lib/
│   ├── common.sh               # Config, logging, formatting, OS detection
│   ├── process.sh              # Process analysis, orphan detection, process tree
│   ├── memory.sh               # Memory, disk, load average
│   └── chrome.sh               # Chrome extensions and memory
├── conf/
│   └── owlwatch.conf.example   # Example config
├── adapters/
│   ├── claude-code.md          # Claude Code skill definition
│   ├── cursor.md               # Cursor rules template
│   └── windsurf.md             # Windsurf rules template
├── install.sh                  # Installer
├── LICENSE                     # MIT
└── README.md
```

## Requirements

- bash 3.2+
- macOS or Linux
- No external dependencies

## License

MIT
