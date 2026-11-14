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

### Checks

The pre-push hook and CI both check every new commit. They reject a message that isn't a conventional commit, a type or scope that isn't in `cog.toml`, and a `feat` or `fix` commit that changes nothing a release ships. To check your commits by hand:

```bash
nix run .#check-commits -- origin/main..HEAD
```

## Pull requests

Open pull requests against `main`. CI builds kantan, runs `nix flake check` and checks the commits.
