# Installation

kantan targets aarch64-darwin only (Apple Silicon Macs). It can be installed via Nix or Homebrew.

## Prerequisites

- macOS Sequoia (15.0) or later on Apple Silicon

A few features depend on the macOS release and on permissions:

- **`focus` module** — reads the Do Not Disturb database when kantan has Full Disk Access, otherwise detects the menu bar's Focus indicator. Without Accessibility permission, that detection is unreliable on Sequoia and can't see whether the indicator is shown on macOS 27. See [Focus — Behavior](/docs/modules/focus#behavior).
- **`mask` configuration** — with Accessibility permission, any menu bar item can be masked on every release. Without it, only system items can. On macOS 27 their positions come from saved defaults that don't follow rearrangement. See [Item Detection](/docs/configuration/masking#item-detection).

Everything else (clock, power, wifi, bluetooth, volume, workspace switching, plugins) works the same on every supported release.

## First-Run Permissions

kantan only asks for a permission when your config uses something that needs it:

- **Accessibility** — requested when kantan loads a config in which a module has a `mask`, or a `focus` module can't read the Focus database. kantan uses it only to read menu bar items. See [Granting Accessibility](/docs/configuration/masking#granting-accessibility).
- **Bluetooth** — requested by the `bluetooth` module the first time it reads Bluetooth state.
- **Optional Full Disk Access** — only lets the `focus` module name the active Focus mode. kantan never asks: macOS has no prompt for it. See [Granting Full Disk Access](/docs/modules/focus#granting-full-disk-access).
- **No Screen Recording or Location prompt.** Menu bar item detection without Accessibility uses window geometry and Control Centre's defaults. The `wifi` module reads the network name from IORegistry.
- **No Automation prompt.** kantan does not send AppleEvents to other applications.

Bundled plugins that read OS data sources prompt the first time they run:

| Plugin | Permission | Trigger |
|--------|------------|---------|
| `reminders` | Reminders (Full Access) | First invocation in normal or watch mode |
| `calendar` | Calendar (Full Access) | First invocation in normal or watch mode |
| `caffeine` | None | Uses `caffeinate(8)` only |
| `pomodoro` | None | Pure local state |
| `system-monitor` | None | Reads public sysctls |
| `tailscale` | None | Talks to `tailscaled` over its Unix socket or runs Tailscale.app's bundled CLI |
| `rift-indicator` | None | Runs the `rift-cli` installed beside the running Rift |

For EventKit plugins (`reminders`, `calendar`), macOS shows the consent dialog under the plugin's bundle identifier. If the binary changes path between invocations (e.g. running it directly vs. through the kantan wrapper), macOS may treat it as a fresh request. Approve once via the dialog or pre-grant in *System Settings → Privacy & Security*.

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

### Homebrew Service

After installing via Homebrew, you can run kantan as a background service, which starts it at login and restarts it if it exits:

```bash
brew services start kantan
```

The service reads its config from the default location (see [Config File Locations](/docs/configuration#config-file-locations)).

### Nix Modules

kantan has modules for both nix-darwin and home-manager. Import the one for your setup:

**nix-darwin:**
```nix
{
  inputs.kantan.url = "github:cmacrae/kantan";

  outputs = { self, darwin, kantan, ... }: {
    darwinConfigurations.myhost = darwin.lib.darwinSystem {
      modules = [
        kantan.darwinModules.default
        {
          programs.kantan.enable = true;
          programs.kantan.settings = {
            height = 33;
            padding = 10;
            modules = [
              { name = "clock"; type = "clock"; placement = "right";
                config = { format = "HH:mm"; }; }
            ];
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

When `settings` is left empty, neither module writes a config. kantan then looks for one in the [default locations](/docs/configuration#config-file-locations).

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
