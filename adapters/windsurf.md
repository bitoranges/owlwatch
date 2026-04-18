# owlwatch — System Performance Monitor (Windsurf Rules)

Add to your `.windsurfrules` or project `.windsurfrules`:

---

## Tool: owlwatch

System performance monitor. Available commands:

- `owlwatch health` — Full system report
- `owlwatch clean` — Scan orphan processes
- `owlwatch clean --yes` — Auto-clean orphans
- `owlwatch clean --name <name>` — Kill processes by name
- `owlwatch clean --pid <PID>` — Kill specific PID
- `owlwatch chrome` — Chrome analysis
- `owlwatch daemon install` — Background auto-cleanup (macOS)

### When to use
- User mentions system performance, slowness, or process issues
- User wants to check what's consuming resources

### Rules
- Run `owlwatch health` before suggesting actions
- Get user confirmation before killing processes
- Never kill protected system processes
