# CLI Reference

kantan has a minimal command-line interface.

**Usage:**
```
kantan [--config <path>] [--modules-dir <path>] [--fonts-dir <path>] [--themes-dir <path>]
kantan trigger <module-name> <action> [key=value ...]
```

**Flags:**

| Flag | Description |
|------|-------------|
| `--config <path>` | Path to configuration file |
| `--modules-dir <path>` | Path to modules.d directory |
| `--fonts-dir <path>` | Path to bundled fonts directory |
| `--themes-dir <path>` | Path to themes directory |

**Config file resolution (in order):**
1. `--config` flag (explicit path)
2. `./config.yaml` (current working directory)
3. `$XDG_CONFIG_HOME/kantan/config.yaml` (defaults to `~/.config/kantan/config.yaml`)

If no config file is found at any of these locations, kantan displays a default welcome bar with a setup hint.

**Modules directory resolution:**
1. `--modules-dir` flag (explicit path)
2. `modules.d/` sibling to the resolved config file

**Fonts directory resolution:**
1. `--fonts-dir` flag (explicit path)
2. `<prefix>/share/fonts/` relative to the kantan binary

**Themes directory resolution:**
1. `--themes-dir` flag (explicit path)
2. `<prefix>/share/themes/` relative to the kantan binary

**Trigger command:**
```
kantan trigger <module-name> <action> [key=value ...]
```

Sends an IPC notification to a running kantan instance via `DistributedNotificationCenter`. Used by watch processes and external scripts to trigger module updates.

- `<module-name>` — The module's `name:` from config (use `*` to target all modules)
- `<action>` — The action to perform
- `[key=value ...]` — Optional key-value pairs included in the notification payload

**Supported actions:**

| Action | Description |
|--------|-------------|
| `refresh` | Re-run the module's data source and update its display |
| `set` | Directly set display properties via key-value pairs: `value=`, `icon=`, `fg=`, `bg=`, `duration=` (auto-reset after N seconds) |

**Examples:**
```bash
kantan trigger my-plugin refresh
kantan trigger my-module set value="Hello" icon="!" duration=5
```
