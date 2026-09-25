# Installation

kantan targets aarch64-darwin only (Apple Silicon Macs). It can be installed via Nix or Homebrew.

## Prerequisites

- macOS Sequoia (15.0) or later on Apple Silicon

While kantan runs on Sequoia (15.0) and later a few individual features depend on behaviour introduced in macOS Tahoe (26.0):

- **`focus` module** — reads the Do Not Disturb database when kantan has Full Disk Access, otherwise falls back to the menu bar's FocusModes indicator. The fallback does not detect focus state correctly on Sequoia.
- **`mask` configuration** — system-item masking works on 15, 26 and 27 (27 reads saved item positions rather than WindowServer windows; see [Item Detection](/docs/configuration/masking#item-detection)), but third-party masking is permanently impossible on 26 due to a Control Centre attribution change (FB18327911). On Sequoia, the same attribution issue exists in a different form. See [Menu Bar Masking — Limitations](/docs/configuration/masking#limitations).

Everything else (clock, power, wifi, bluetooth, volume, workspace switching, plugins) works identically on both releases.

## First-Run Permissions

kantan itself does not prompt for any TCC permissions on first launch:

- **No Accessibility prompt.** kantan does not call `AXIs…` or any other Accessibility API.
- **No Screen Recording prompt.** Menu bar item detection uses `CGWindowListCopyWindowInfo`, which returns window geometry without Screen Recording permission. (Window titles are gated, but kantan does not rely on them.) On macOS 27 and later it reads saved item positions from Control Centre's defaults instead, which need no permission either.
- **Optional Full Disk Access.** Granting it lets kantan follow menu bar items rearranged on macOS 27 and lets the `focus` module name the active Focus mode. See [Granting Full Disk Access](/docs/configuration/masking#granting-full-disk-access).
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

For EventKit plugins (`reminders`, `calendar`), macOS shows the consent dialog under the plugin's bundle identifier. If the binary changes path between invocations (e.g. running it directly vs. through the kantan wrapper), macOS may treat it as a fresh request. Approve once via the dialog or pre-grant in *System Settings → Privacy & Security*.

## Installation Methods

### Homebrew

```bash
brew tap cmacrae/kantan
brew install kantan
```

A variant without plugins is also available:

```bash
brew install kantan-without-plugins
```

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

After installing via Homebrew, you can run kantan as a background service:

```bash
brew services start kantan
```

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
| `programs.kantan.extraPackages` | list of packages | `[]` | Extra packages added to kantan's PATH (e.g., `aerospace`) |
| `programs.kantan.fonts` | list of packages | `[]` | Font packages to install (nix-darwin only) |

Both modules create a launchd agent that starts kantan at login. The nix-darwin module passes the config via `--config` flag; the home-manager module writes it to `~/.config/kantan/config.yaml` via XDG config files.

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

The flake exposes one extra top-level package output for convenience, plus a small surface of passthru attributes on the default derivation:

**Flake outputs (`kantan.packages.aarch64-darwin.*`)**

- `default` — the wrapped binary with all bundled plugins, themes, and fonts (also exposed as `kantan`)
- `without-plugins` — wrapped binary with bundled fonts and themes but no plugins

**Passthrus on `kantan.packages.aarch64-darwin.default`**

These are convenience attributes attached to the default derivation, not separate flake outputs. They are reachable as e.g. `inputs.kantan.packages.aarch64-darwin.default.withoutPlugins`:

- `withoutPlugins` — the bare unwrapped binary with no plugins, themes, or bundled fonts
- `withPlugins` — function form of `override` ({ plugins ? …, themes ? …, … } → derivation)
- `override` — alias for `withPlugins`, mirroring nixpkgs convention
- `plugins` — attribute set of individual plugin packages
- `themes` — attribute set of individual theme packages

The top-level outputs use kebab-case (`without-plugins`). The derivation passthrus use camelCase (`withoutPlugins`), matching the Swift-side naming. Both are plugin-less builds. The flake output keeps fonts and themes bundled. The passthru is a bare binary.
