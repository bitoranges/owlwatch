# owlwatch — System Performance Monitor (Cursor Rules)

Copy this into your `.cursorrules` or `.cursor/rules/owlwatch.md`:

---

## Tool: owlwatch

System performance monitor. Available commands:

- `owlwatch health` — Full system report (CPU, memory, disk, load, orphans, process tree)
- `owlwatch clean` — Scan orphan processes (dry run)
- `owlwatch clean --yes` — Auto-clean detected orphans
- `owlwatch clean --name <name>` — Kill processes by name
- `owlwatch clean --pid <PID>` — Kill specific PID
- `owlwatch chrome` — Chrome memory and extension analysis
- `owlwatch daemon install` — Install background auto-cleanup (macOS)

### When to use
- User mentions system slowness, high CPU, fan noise, memory issues
- User asks to check or clean processes
- User wants Chrome resource analysis

### Rules
- Always run `owlwatch health` first before suggesting actions
- Explain findings in plain language
- Get explicit user confirmation before killing any process
- Never suggest killing system processes (kernel_task, WindowServer, etc.)
