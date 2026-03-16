# Quick Start

This guide walks through creating a minimal kantan configuration and running it.

## Step 0: Run Without Config

You can run kantan immediately with no config file. It shows a welcome bar with a setup hint:

```bash
kantan
```

When you're ready to customise, proceed to the steps below.

## Step 1: Create Config Directory

```bash
mkdir -p ~/.config/kantan
```

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

  - name: battery
    type: power
    placement: right
```

See the Configuration and Modules sections for complete details on available modules and their options.

## Reference Configuration

The `examples/` directory in the kantan repository contains a reference configuration with a `config.yaml` and `modules.d/` files demonstrating several modules and plugins.
