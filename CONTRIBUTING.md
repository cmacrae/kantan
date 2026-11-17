# Contributing to kantan

Thanks for helping out. This guide covers setting up, checking your changes and writing commit messages.

## Setting up

kantan builds with Nix, with flakes enabled. Everything you need comes from the dev shell:

```bash
nix develop
```

With [direnv](https://direnv.net), run `direnv allow` once and the dev shell loads whenever you enter the repository.

The dev shell also installs a pre-push hook that checks your commits before they leave your machine. If you already have a pre-push hook, the dev shell leaves it alone and says so.

## Building and checking

| Command | What it does |
|---------|--------------|
| `nix run` | Builds kantan and runs it |
| `nix build` | Builds kantan into `result/` |
| `nix fmt` | Formats the code |
| `nix flake check` | Builds everything and runs the tests and checks |
| `nix run .#docs` | Serves the docs at http://localhost:3000 |
| `nix run .#site` | Serves the website and docs at http://localhost:3000 |
| `nix run .#snapshot -- <page> <width> <height> <scale> <out.png> [script]` | Draws a page to a PNG with WebKit, after running a script in it |

Run `nix fmt` and `nix flake check` before you push. New files must be added with `git add` before Nix can see them.

## Commit messages

Commits follow [Conventional Commits](https://www.conventionalcommits.org): `type(scope): description`. The version number comes from them. The type says whether a change reaches kantan's users.

`feat` and `fix` are only for changes to what a release ships: kantan, its bundled plugins and themes, and its icon font. They're the only types that bump the version.

| Type | Use it for | Version |
|------|------------|---------|
| `feat` | New behaviour in kantan or a bundled plugin | Minor |
| `fix` | A bug fix in kantan or a bundled plugin | Patch |
| `perf` | Faster code, same behaviour | None |
| `refactor` | Restructured code, same behaviour | None |
| `docs` | The documentation | None |
| `site` | The website | None |
| `build` | Packaging and the Nix tooling | None |
| `ci` | The workflows | None |
| `test` | Tests only | None |
| `chore`, `style` | Anything else | None |

Add `!` after the type or scope for a change that breaks existing configs or plugins, for example `feat(workspace)!: …`. That bumps the major version.

### Scopes

The scope names the part of kantan a commit changes. It's optional, but it must come from the list in [`cog.toml`](cog.toml):

- **The app:** `bar`, `config`, `cli`, `display`, `events`, `interaction`, `masking`, `dsl`, `theme`, `icons`
- **Built-in modules:** each module's type, such as `clock` or `workspace`, or `modules` for changes to several
- **Bundled plugins:** each plugin's name, such as `pomodoro`, or `plugins` for changes to several
- **Packaging and tooling:** `nix`, `homebrew`, `release`, `install`, with types that don't bump the version

A new module or plugin needs its scope added to `cog.toml`. `nix flake check` fails until it is.

## Plugin previews

Each bundled plugin's docs page shows the plugin in an interactive bar. The preview is generated when the docs are built, from two things in the plugin's directory:

- `examples/00-<name>.yaml`, the module the preview draws.
- `preview/`, a generator that prints the states the preview moves between.
- `settings.schema.json`, a JSON schema of the plugin's `config.settings`. The builder makes the plugin's settings form from it.

The generator is built from the plugin's own code. Its `main.swift` or `main.go` takes the place of the plugin's, so keep the plugin's own `main` file to its entry point and put everything else in other files. A shell plugin's `preview/main.sh` is given the path of the plugin's `main.sh` to run. The generator gets the example config's settings in `KANTAN_SETTINGS`, as kantan gives them to the plugin.

It prints one JSON object:

```json
{
  "states": [
    {
      "name": "Idle",
      "output": { "value": "25:00" },
      "after": { "kantan-plugin-pomodoro --start": { "value": "24:59" } }
    }
  ]
}
```

`output` is exactly what the plugin prints in that state. `after` is optional: for each command the state's menu, popup or toggle runs, the output the plugin prints once it has run. A command that leads to another state's output moves the preview to that state.

In the schema, give a colour `"$ref": "module-config.schema.json#/$defs/Color"` and an icon `"$ref": "module-config.schema.json#/$defs/Icon"`. A preview follows those settings when they change in the builder. For that, a plugin must print a colour or an icon exactly as it was given it. A setting that can be written more than one way lists the plainest way first in its `oneOf`.

`nix flake check` fails for a plugin without a schema, for an example whose settings the schema rejects, for a plugin that prints a colour or an icon other than as given, and for a schema default that isn't the plugin's. It also fails for a plugin without a generator, for output the [plugin output schema](docs/schemas/plugin-output.schema.json) rejects, for an `after` command no state runs, and for a preview holding something the web preview can't draw. [`web/README.md`](web/README.md) covers the web side.

### Checks

The pre-push hook and CI both check every new commit. They reject a message that isn't a conventional commit, a type or scope that isn't in `cog.toml`, and a `feat` or `fix` commit that changes nothing a release ships. To check your commits by hand:

```bash
nix run .#check-commits -- origin/main..HEAD
```

## Pull requests

Open pull requests against `main`. CI builds kantan, runs `nix flake check` and checks the commits.
