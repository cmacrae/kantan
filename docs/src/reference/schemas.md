# Schemas

kantan has JSON schemas for validating plugin output and module configuration.

**Plugin Output Schema**

Defines the JSON format that plugins must output to stdout.

Location: `docs/schemas/plugin-output.schema.json`

Key fields:
- `value` — display text (optional; raw stdout used if omitted)
- `icon` — icon override
- `hidden` — hide module
- `active` — active state
- `variables` — template variables for `{key}` substitution
- `data` — named data arrays for `foreach` iteration in the View DSL
- `style` — dynamic color overrides (fg, bg, icon, text)
- `view` — View DSL tree for rich popup/menu/tooltip content

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

**Using schemas for validation:**

You can use any JSON Schema validator to check your configuration or plugin output against these schemas. For example, with `ajv`:
```bash
ajv validate -s docs/schemas/plugin-output.schema.json -d my-plugin-output.json
```
