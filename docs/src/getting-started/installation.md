# Installation

kantan targets aarch64-darwin only (Apple Silicon Macs). It can be installed with Homebrew, Nix or an install script.

## Prerequisites

- macOS Sequoia (15.0) or later on Apple Silicon

## First-Run Permissions

kantan only asks for a permission when your config uses something that needs it:

- **Accessibility** — requested when kantan loads a config in which a module has a `mask`, or a `focus` module can't read the Focus database. kantan uses it only to read menu bar items. See [Granting Accessibility](../configuration/masking.md#granting-accessibility).
- **Bluetooth** — requested by the `bluetooth` module the first time it reads Bluetooth state.
- **Optional Full Disk Access** — only lets the `focus` module name the active Focus mode. kantan never asks: macOS has no prompt for it. See [Granting Full Disk Access](../modules/focus.md#granting-full-disk-access).

Bundled plugins that read OS data sources prompt the first time they run:

| Plugin | Permission | Trigger |
|--------|------------|---------|
| `reminders` | Reminders (Full Access) | First invocation in normal or watch mode |
| `calendar` | Calendar (Full Access) | First invocation in normal or watch mode |

For EventKit plugins (`reminders`, `calendar`), macOS shows the consent dialog under the plugin's bundle identifier. If the binary changes path between invocations (e.g. running it directly vs. through the kantan wrapper), macOS may treat it as a fresh request. Approve once via the dialog or pre-grant in *System Settings → Privacy & Security*.

### After Upgrading

kantan and its plugins are signed ad hoc, so macOS ties each permission to the exact binary it was granted to. After an upgrade, macOS may ask again, or show the old entry in *System Settings → Privacy & Security* while it no longer applies. If a module stops working after an upgrade, remove kantan's or the plugin's entry from the list and grant it again.

## Installation Methods

### Homebrew

```bash
brew install cmacrae/tap/kantan
```

A variant without plugins is also available. It conflicts with `kantan`. Install one or the other:

```bash
brew install cmacrae/tap/kantan-without-plugins
```

Both formulae install the bundled icon fonts and themes alongside the binary.

### Install Script

```bash
curl -fsSL https://kantan.bar/install.sh | sh
```

The script installs the latest release into `~/.local/lib/kantan` and links its binaries into `~/.local/bin`. It tells you if that isn't on your `PATH`. Pass options after `sh -s --`:

```bash
curl -fsSL https://kantan.bar/install.sh | sh -s -- --version 0.1.0
```

| Option | Description |
|--------|-------------|
| `--prefix <dir>` | Install under `<dir>` instead of `~/.local` |
| `--version <version>` | Install `<version>` instead of the latest release |
| `--without-plugins` | Install kantan without its bundled plugins |
| `--uninstall` | Remove kantan from the prefix |

The script checks the download against the release's `SHA256SUMS` and stops if they don't match. That catches a corrupted download, not a tampered release. To check where a release's files were built, verify their build provenance with the [GitHub CLI](https://cli.github.com):

```bash
gh attestation verify kantan-0.1.0-aarch64-darwin.tar.gz --repo cmacrae/kantan
```

Running it again replaces the installed release. It never overwrites a file in `bin` that isn't one of its links. The install also includes a launchd agent that starts kantan at login (see [Install Script Agent](#install-script-agent)).

### Nix Flake

kantan is distributed as a Nix flake. This requires the Nix package manager with flakes enabled.

#### Run Directly

```bash
nix run github:cmacrae/kantan
```

#### Add to a Flake

```nix
{
  inputs.kantan.url = "github:cmacrae/kantan";

  # kantan is available as:
  # inputs.kantan.packages.aarch64-darwin.default
}
```

#### Install to Profile

```bash
nix profile install github:cmacrae/kantan
```

## Plugin Customization

The default package includes all built-in plugins and themes. To customize which plugins are included:

```nix
kantan.packages.aarch64-darwin.default.override {
  plugins = [];              # no plugins
  extraPlugins = [ myPlugin ];  # add custom plugins
  themes = [];               # no themes
}
```

### Additional Package Variants

The flake exposes one extra user-facing package output, plus a few passthru attributes on the default derivation:

**Flake outputs (`kantan.packages.aarch64-darwin.*`)**

- `default` — the wrapped binary with all bundled plugins, themes, and fonts (also exposed as `kantan`)
- `without-plugins` — wrapped binary with bundled fonts and themes but no plugins

**Passthrus on `kantan.packages.aarch64-darwin.default`**

These are convenience attributes attached to the default derivation, not separate flake outputs. They are reachable as e.g. `inputs.kantan.packages.aarch64-darwin.default.withoutPlugins`:

- `withoutPlugins` — the bare unwrapped binary with no plugins, themes, or bundled fonts (so icon names render as plain text unless kantan is given a fonts directory with `--fonts-dir`)
- `withPlugins` — function form of `override` ({ plugins ? …, themes ? …, … } → derivation)
- `override` — alias for `withPlugins`, mirroring nixpkgs convention
- `plugins` — attribute set of individual plugin packages
- `themes` — attribute set of individual theme packages

The top-level outputs use kebab-case (`without-plugins`). The derivation passthrus use camelCase (`withoutPlugins`), matching the Swift-side naming. Both are plugin-less builds. The flake output keeps fonts and themes bundled. The passthru is a bare binary.

## Running kantan

Run `kantan` in a terminal to try it out. To start it at login, and restart it if it exits, run it as a launchd agent with the method that suits your install. Each agent loads your config from the [default locations](../configuration/index.md#config-file-locations).

### Homebrew Service

```bash
brew services start kantan
```

Use `kantan-without-plugins` in place of `kantan` if that's the formula you installed. `brew services stop kantan` stops kantan and removes it from login.

### Install Script Agent

The install script writes a launchd agent for the kantan it installs to `<prefix>/lib/kantan/share/examples/bar.kantan.plist`. The agent runs kantan with `<prefix>/bin`, Homebrew's `bin` directories and the system's on its `PATH`, so `command` modules find the tools installed there. With the default prefix, copy it into `~/Library/LaunchAgents` and load it:

```bash
cp ~/.local/lib/kantan/share/examples/bar.kantan.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/bar.kantan.plist
```

To stop kantan and remove it from login:

```bash
launchctl bootout gui/$(id -u)/bar.kantan
rm ~/Library/LaunchAgents/bar.kantan.plist
```

Do this before uninstalling kantan with the script.

### Nix Modules

kantan has modules for both nix-darwin and home-manager. Import the one for your setup:

**nix-darwin:**
```nix
{
  inputs.kantan.url = "github:cmacrae/kantan";

  outputs =
    { darwin, kantan, ... }:
    {
      darwinConfigurations.myhost = darwin.lib.darwinSystem {
        modules = [
          kantan.darwinModules.default
          {
            programs.kantan = {
              enable = true;
              settings = {
                height = 33;
                padding = 10;
                modules = [
                  {
                    name = "clock";
                    type = "clock";
                    placement = "right";
                    config.format = "HH:mm";
                  }
                ];
              };
            };
          }
        ];
      };
    };
}
```

**home-manager:**
```nix
{
  inputs.kantan.url = "github:cmacrae/kantan";

  # In your home-manager configuration:
  imports = [ kantan.homeManagerModules.default ];

  programs.kantan = {
    enable = true;
    settings = { /* your config as Nix attrset */ };
  };
}
```

#### Module Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `programs.kantan.enable` | bool | `false` | Enable kantan |
| `programs.kantan.package` | package | kantan default | Package to install |
| `programs.kantan.settings` | attrset | `{}` | Configuration written as `config.yaml` |
| `programs.kantan.themes` | attrset of attrsets | `{}` | Custom themes; each key becomes `<name>.yaml` in the themes directory |
| `programs.kantan.extraArgs` | list of strings | `[]` | Extra CLI arguments passed to kantan |
| `programs.kantan.extraPackages` | list of packages | `[]` | Extra packages added to kantan's PATH (e.g., tools run by `command` modules) |
| `programs.kantan.fonts` | list of packages | `[]` | Font packages to install (nix-darwin only) |

Both modules create a launchd agent that starts kantan at login and restarts it if it exits. The modules install kantan wrapped with `extraArgs`, and with `extraPackages` on its `PATH`.

- **nix-darwin** passes `settings` with the `--config` flag, pointing at a generated file in the Nix store. That file has no `modules.d/` beside it. To use one, pass its path with `extraArgs = [ "--modules-dir" "/path/to/modules.d" ];`. `themes` are combined with the package's bundled themes into a directory passed with `--themes-dir`.
- **home-manager** writes `settings` to `~/.config/kantan/config.yaml` and each of `themes` to `~/.config/kantan/themes/<name>.yaml`. A `modules.d/` in `~/.config/kantan` is picked up as usual.

When `settings` is left empty, neither module writes a config. kantan then looks for one in the [default locations](../configuration/index.md#config-file-locations).


### Logs

kantan logs config errors, reloads and skipped modules to standard output. Where they end up depends on how kantan was started:

| Started by | Log |
|------------|-----|
| A terminal | The terminal |
| `brew services` | `$(brew --prefix)/var/log/kantan.log` |
| The install script's agent | `~/Library/Logs/kantan.log` |
| The Nix modules | `~/Library/Logs/kantan.log` |

Follow a log file with `tail -f`. Console.app also lists `~/Library/Logs` under *Log Reports*.
