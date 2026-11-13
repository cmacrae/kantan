# Schemas

kantan has JSON schemas for validating plugin output and module configuration.

**Plugin Output Schema**

Defines the JSON format that plugins must output to stdout.

Location: `docs/schemas/plugin-output.schema.json`

Key fields:
- `value` — display text (optional; raw stdout used if omitted)
- `segments` — the value in parts, each with its own colour
- `icon` — icon override (icon name or glyph)
- `hidden` — hide module
- `active` — active state
- `variables` — template variables for `{key}` substitution
- `data` — named data arrays for `foreach` iteration in the View DSL
- `style` — dynamic colour overrides (fg, bg, icon, text)
- `view` — View DSL tree for the module's click menu or popup

kantan ignores fields it doesn't know. The schema rejects them to catch typos.

See the [Plugin API Reference](../plugins/api-reference.md) for detailed field documentation.

**Module Configuration Schema**

Defines the YAML configuration format for modules.

Location: `docs/schemas/module-config.schema.json`

Covers:
- Common module fields (name, type, placement, icon, fonts, style, interaction, mask, displays, config)
- Type-specific configuration for all built-in module types
- Command module configuration (for plugins)
- Interaction configuration (hover/click)
- Style configuration (per-appearance)
- Placement specification (including or-wise syntax)

See the [Configuration](../configuration/modules.md) section for human-readable documentation.

**Schema draft:**

Both schemas target [JSON Schema draft 2020-12](https://json-schema.org/draft/2020-12) (declared via their `$schema` keyword).
Validators that understand this draft — `ajv-cli` (with `--spec=draft2020`), `jsonschema` (Python ≥ 4.18), `check-jsonschema`, IntelliJ, VS Code's built-in YAML/JSON support — will work out of the box.

**Using schemas for validation:**

You can use any JSON Schema validator to check your configuration or plugin output against these schemas. For example, with `ajv-cli`:
```bash
ajv validate --spec=draft2020 -s docs/schemas/plugin-output.schema.json -d my-plugin-output.json
```

**Editor integration:**

Two common setups check against the schemas as you type:

- **`yaml-language-server` (VS Code, Neovim, Helix, etc.)** — add a modeline at the top of `config.yaml` or any file in `modules.d/`:
  ```yaml
  # yaml-language-server: $schema=https://raw.githubusercontent.com/cmacrae/kantan/main/docs/schemas/module-config.schema.json
  ```
  This enables autocompletion, hover docs, and inline diagnostics for module configuration. Replace `main` with a tag if you want to pin to a released version of the schema.

- **JSON files (plugin output, scratch files)** — point your editor's JSON schema mapping at `docs/schemas/plugin-output.schema.json`. In VS Code, add it to `json.schemas` in `settings.json`:
  ```json
  "json.schemas": [
    {
      "fileMatch": ["plugin-output*.json"],
      "url": "https://raw.githubusercontent.com/cmacrae/kantan/main/docs/schemas/plugin-output.schema.json"
    }
  ]
  ```

**Versioning and evolution:**

The schemas are versioned with kantan itself and have no version number of their own. Breaking changes to either schema (renaming required fields, removing supported values) will be called out in the kantan release notes. Additive changes (new optional fields, new module types) may land in any release without an announcement. Validate with the schema from the same commit as the kantan binary you run.
