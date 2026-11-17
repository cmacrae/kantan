# Shared cases

Each file lists inputs with the result kantan gives for them. kantan's tests
and the web engine's tests both run every case, so the engine can't drift
from kantan without a check failing.

An `expect` value is compared as a subset: every key it has must match, and
keys it leaves out aren't compared. A list must match item for item, and
`null` means the key is absent.

| File | A case is | It expects |
|------|-----------|------------|
| `templates.json` | variables, data, foreach scopes and an optional palette | what each template resolves to, as text, a command, a boolean or a condition |
| `themes.json` | theme files and a config's `theme` | the light and dark palettes, or `null` when the theme doesn't load |
| `menus.json` | a view from plugin JSON or config YAML, with variables and data | the native menu's rows, or that the view is rejected |
| `bars.json` | a document | for each appearance checked, the bar and its modules |
| `modules.json` | a document whose states hold what a built-in module reads | for each state checked, the module as the bar shows it |

A built-in module reads the system: the battery's level, the workspaces, the
time. A case gives it a sample of that reading as its state's `output`, and
`web/engine/modules/` describes each type's sample.

The icon table is empty in every case. An icon is then the name it was given.
