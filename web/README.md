# web

The website, and kantan's bar drawn in the browser: the landing page, the docs' plugin previews, and the config builder with its theme builder all draw from the one engine here.

| Directory | What it holds |
|-----------|---------------|
| `engine/` | kantan's config, theme, style, template and View DSL semantics in plain JavaScript, with no React and no DOM. It turns a document into a bar ready to draw. |
| `builder/` | What the builder does to a document, with no React and no DOM: its edits to configs and themes, the YAML files it writes, share links, and the SVG a share image is made from. |
| `components/` | React components that draw what the engine resolves: the bar, a module, its menu, popup and tooltip, and the mock desktop a bar is shown on. |
| `apps/` | The pages built from them: `landing/`, `docs-preview/` and `builder/`. |
| `previews/` | Assembles preview documents from generators' output: each bundled plugin's, and a whole bar's such as the landing page's. |
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
  },
  "view": { "dark": true, "notch": false, "shown": { "calendar": "Underway" } }
}
```

`config`, `modulesDir` and `themes` mirror config.yaml, modules.d and the theme files. The engine loads them as kantan loads the files. `resolveBar(document, options)` returns the bar for one appearance, with each module in the state `options.states` names.

A state's `output` is what its module would read. For a command module that is what its command printed. For a module that reads the system it is a sample of the reading: `{ "level": 78 }` for the battery, the list of workspaces, the time. Each file in `engine/modules/` describes its type's sample. `options.samples` gives a module a reading in place of its state's, which is how a page keeps a clock ticking or switches workspace.

`view` says how the bar is being looked at: the appearance, whether the screen has a notch, and the state each module shows. A shared bar opens as its sharer saw it.

`components/useBar.js` holds a bar as someone uses it. It follows the commands they run, the drawers they open and the workspace they switch to.

## The landing page's bar

The landing page draws the config it shows, `apps/landing/content/config-example.yaml`. `nix/site.nix` assembles its document with `previews/bar.js`: the config, the built-in modules' samples in `apps/landing/content/states.json`, and the states of its plugins from their own generators. The build fails when the engine can't draw any of it. The README's images are drawn from the same bar.

## The builder

`apps/builder/` is the page at `/builder/`. It draws a document's bar live, lists its modules, edits whichever is picked, and shows the YAML that makes the bar.

The bar has two ways of answering the pointer. While customising, a click on a module drops its quick settings and a drag moves it. While trying it out, the bar behaves as it does in kantan. Modules set over the menu bar can't be moved, because macOS decides where its own items sit.

- **Settings** are forms made from `docs/schemas/module-config.schema.json`, so a key the schema gains appears in the builder. Any module can also be edited as YAML.
- **Preview data** is the module's states. A built-in module's state is a sample of the system, set with controls for its type. A command module's is the output its command printed, edited as text, with the state each of its commands leads to.
- **The example bar** it opens with is the landing page's, in the states shown there.
- **What can be added** is each module type (`builder/catalog.js`), each bundled plugin, and a plugin of someone's own from output they paste. `nix/previews.nix` builds the catalogue of bundled plugins from their preview generators, and every Tabler icon with its scale.
- **The YAML** is written by `builder/files.js` in either layout: one `config.yaml`, or a file for each module in `modules.d`. The builder itself works on a document with every module in `config.yaml`, in the order drawn.

A bundled plugin's states are what its generator prints for its example settings. Changing the settings in the builder changes the YAML but not the states.

### Themes

The builder's editor is on one thing at a time: the bar's settings, a module, or a theme. Bar Settings lists the themes. One of kantan's can be copied, a new one started, or a theme file pasted in.

A theme being edited is a theme file in the document's `themes`, exactly as kantan would read it from `themes/<name>.yaml`. `builder/theme.js` holds its edits: the three kinds of file, colours added, renamed and removed in every palette at once, and flavours. While a theme is edited the bar is drawn in the palette being edited, whatever the config selects.

A Base16 or Base24 scheme can be imported too, pasted in or picked from a gallery: one for both appearances, or one for light and another for dark. `builder/base16.js` reads a scheme and makes its theme: one palette, with a colour for each slot. A config that names Catppuccin's colours is rewritten to name the slots holding them, as Catppuccin's own scheme lays them out, wherever both appearances' palettes have the slot. The example bar is drawn in an imported scheme straight away.

The gallery is the tinted-theming project's schemes, which the browser lists and fetches from GitHub when the import dialog opens. It shows only while that listing is laid out as `readListing` expects and its first file reads as a scheme. Otherwise the dialog offers pasting alone. The browser keeps the listing, and each scheme it has drawn, in local storage for a day.

`builder/files.js` writes the theme's file, or a directory with a file for each flavour. A config's own files include the themes it selects, because kantan won't load a config whose theme is missing.

### Share links

A link holds a whole document in the address's fragment, so the site stores nothing. `builder/share.js` packs the document, deflates it and writes it as base64url after the codec's version: `/builder/#1.<data>`.

The document's themes travel with it. Packing keeps links short. States a module starts with, or has in the example bar, are left out and restored from the catalogue when the link opens. The words nearly every config uses are written as tokens from the list in `builder/words.js`. That list only ever grows at its end, because a word's place is its token. The example bar's link is about 750 characters.

A fragment can instead name a config file for the browser to fetch: `#from=<url>`, `#gh=<user>/<repo>/<path>` or `#gist=<id>`. Such a link is short and always shows the file as it is, with each module in the states it starts with.

### Share images

The Share dialog makes a PNG of the bar on the mock desktop, in light, dark or both, laid out as the README's images are. `apps/builder/ShareImage.jsx` draws the desktop off the page with `components/Desk.jsx`, the same component the landing page and the README's images use. It serialises that into an SVG image as a foreign object with its fonts held within (`builder/image.js`), then draws the SVG onto a canvas. The image is made by the browser's own renderer from the builder's own components. No second renderer has to be kept in step.

## Staying faithful to kantan

`fixtures/` holds inputs with the results kantan gives for them. kantan's tests (`packages/kantan/Tests/kantanTests/ConformanceTests.swift`) and the engine's (`engine/test/conformance.test.js`) both run every case, so a difference between kantan and the engine fails `nix flake check`. When kantan's behaviour changes, change the case with it.

Anything kantan draws that the engine or the components can't yet is drawn as a "not supported in preview" marker, never left out.

One thing has no shared cases: where a masked module sits. kantan puts it over a menu bar item wherever macOS has put that item. `engine/menubar.js` holds the widths of the system's items as measured on a Mac. The engine lays masked modules out from those widths. The same file holds the size of a MacBook's notch, which the bar is drawn around on a screen that has one.

## Building

Everything builds through Nix. `nix/web.nix` bundles the apps and runs the engine's and the builder's tests, `nix/previews.nix` builds and runs the plugins' preview generators, and `nix/site.nix` and `nix/docs.nix` assemble the site and the docs from them.
