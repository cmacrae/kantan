# web

The website, and kantan's bar drawn in the browser: the landing page, the docs' plugin previews and, later, the config and theme builders all draw from the one engine here.

| Directory | What it holds |
|-----------|---------------|
| `engine/` | kantan's config, theme, style, template and View DSL semantics in plain JavaScript, with no React and no DOM. It turns a document into a bar ready to draw. |
| `components/` | React components that draw what the engine resolves: the bar, a module, its menu, popup and tooltip. |
| `apps/` | The pages built from them: `landing/` and `docs-preview/`. |
| `previews/` | Assembles each bundled plugin's preview document from its generator's output. |
| `fixtures/` | The cases kantan's tests and the engine's tests both run. |
| `static/` | Files served as they are: the pages' HTML, the favicon, the install script. |
| `images/`, `snapshot/` | The README's images, and the WebKit tool that renders them. |

## Documents

Everything the engine draws is a document: a user's config files as parsed YAML, and the states its modules show. `engine/document.js` describes and validates it.

```json
{
  "version": 1,
  "config": { "theme": "catppuccin", "modules": [] },
  "modulesDir": { "00-calendar.yaml": { "name": "calendar", "type": "command" } },
  "themes": { "catppuccin": {} },
  "states": {
    "calendar": [{ "name": "Upcoming", "output": {}, "transitions": { "<command>": "Underway" } }]
  }
}
```

`config`, `modulesDir` and `themes` mirror config.yaml, modules.d and the theme files. The engine loads them as kantan loads the files. `resolveBar(document, options)` returns the bar for one appearance, with each module in the state `options.states` names.

## Staying faithful to kantan

`fixtures/` holds inputs with the results kantan gives for them. kantan's tests (`packages/kantan/Tests/kantanTests/ConformanceTests.swift`) and the engine's (`engine/test/conformance.test.js`) both run every case, so a difference between kantan and the engine fails `nix flake check`. When kantan's behaviour changes, change the case with it.

Anything kantan draws that the engine or the components can't yet is drawn as a "not supported in preview" marker, never left out.

## Building

Everything builds through Nix. `nix/web.nix` bundles the apps and runs the engine's tests, `nix/previews.nix` builds and runs the plugins' preview generators, and `nix/site.nix` and `nix/docs.nix` assemble the site and the docs from them.
