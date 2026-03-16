# Installation

kantan targets aarch64-darwin only (Apple Silicon Macs). It can be installed via Nix or Homebrew.

## Prerequisites

- macOS Sequoia (15.0) or later on Apple Silicon

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

- `kantan.packages.aarch64-darwin.without-plugins` — bundled fonts and themes but no plugins
- `kantan.packages.aarch64-darwin.default.withoutPlugins` — bare binary only (no plugins, themes, or bundled fonts)
- `kantan.packages.aarch64-darwin.default.plugins` — attribute set of individual plugin packages
- `kantan.packages.aarch64-darwin.default.themes` — attribute set of individual theme packages
