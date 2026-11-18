# Quick Start

This guide walks through creating a minimal kantan configuration and running it.

To start without writing YAML, use the [builder](https://kantan.bar/builder/). It draws a bar in the browser as you pick its modules, and writes the config files for it.

## Step 0: Run Without Config

You can run kantan immediately with no config file. It shows a welcome bar with a setup hint:

```bash
kantan
```

kantan checks for a config file every couple of seconds and loads it as soon as you create one.

## Step 1: Create Config Directory

```bash
mkdir -p ~/.config/kantan
```

kantan loads `~/.config/kantan/config.yaml`, or `$XDG_CONFIG_HOME/kantan/config.yaml` when `XDG_CONFIG_HOME` is set. `kantan --config <path>` loads a config from anywhere else. See [Config File Locations](../configuration/index.md#config-file-locations).

## Step 2: Create a Minimal Config

Create `~/.config/kantan/config.yaml`:

```yaml
height: 33
padding: 10

modules:
  - name: clock
    type: clock
    placement: right
    config:
      format: "HH:mm"
```

## Step 3: Run kantan

```bash
kantan
```

Or with an explicit config path:

```bash
kantan --config ~/.config/kantan/config.yaml
```

A status bar appears with a clock showing the current time.

## Step 4: Edit and Reload

kantan reloads when you edit your configuration file. Try changing the clock format:

```yaml
config:
  format: "HH:mm:ss"  # now shows seconds
```

Save the file and the bar updates without a restart.

## Step 5: Add More Modules

You can add more modules to build out your status bar. For example:

```yaml
modules:
  - name: clock
    type: clock
    placement: right
    config:
      format: "HH:mm"

  - name: power
    type: power
    placement: right
```

Modules with the same placement appear left to right in the order they're listed. Here the battery sits at the far right with the clock to its left. See the [Configuration](../configuration/index.md) and [Built-in Modules](../modules/index.md) sections for every module and its options.

The [builder](https://kantan.bar/builder/) adds, arranges and edits modules on a bar drawn live. It can open a config you paste, to carry on from the one written here.

## Reference Configuration

kantan installs example configs you can copy from, under `share/examples/` in its install prefix:

| Install | Examples |
|---------|----------|
| Homebrew | `$(brew --prefix kantan)/share/examples/` |
| Install script | `~/.local/lib/kantan/share/examples/` |
| Nix | `share/examples/` in the kantan package |

`reference/` holds a full reference configuration: a `config.yaml` and a `modules.d/` using several modules and plugins. Each bundled plugin also has a module file, such as `00-calendar.yaml`, to drop into your `modules.d/`. The same files are in the kantan repository, in `examples/` and in each plugin's `examples/`.
