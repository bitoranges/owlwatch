# /owlwatch — System Performance Monitor

## Trigger
User says "/owlwatch", "check system", "system health", "fan noisy", "computer slow", "kill process", "clean processes", "Chrome analysis", "memory analysis", "process monitor", etc.

## Command Routing

| User intent | Command |
|-------------|---------|
| System health / check system | `owlwatch health` |
| Clean processes / kill processes | `owlwatch clean` |
| Confirm clean | `owlwatch clean --yes` |
| Kill specific PID | `owlwatch clean --pid <PID>` |
| Kill by name | `owlwatch clean --name <name>` |
| Chrome analysis | `owlwatch chrome` |
| Install daemon | `owlwatch daemon install` |
| Uninstall daemon | `owlwatch daemon uninstall` |
| Daemon status | `owlwatch daemon status` |

## Execution Flow

1. Run `owlwatch health` to get a full report.
2. Summarize key findings in user's language — prioritize warnings.
3. List safe-to-kill orphan processes with PIDs.
4. Ask user to confirm before cleaning.
5. After cleaning, run `owlwatch health` again to verify.

## Output Rules
- Use the user's preferred language
- Use emoji status markers: normal, warning, critical
- Human-readable values (GB, MB, %)

## Safety
- Only suggest killing orphan processes (no terminal + high CPU + long runtime)
- Never kill protected processes (kernel_task, WindowServer, loginwindow, etc.)
- Always get explicit user confirmation before killing
- Don't auto-install daemon

## Stop Hook (optional)
```json
{
  "hooks": {
    "Stop": [
      {
        "command": "owlwatch health",
        "description": "System health report on session end"
      }
    ]
  }
}
```
