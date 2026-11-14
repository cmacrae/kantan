export default [
  {
    label: "Nix",
    content: `# Try it
nix run github:cmacrae/kantan

# Install to profile
nix profile install github:cmacrae/kantan

# Or use the nix-darwin / Home Manager module
programs.kantan.enable = true;`,
    note: {
      text: "See the docs for nix-darwin and Home Manager module options",
      href: "/docs/getting-started/installation.html#nix-modules",
    },
  },
  {
    label: "Homebrew",
    content: `# Install
brew install cmacrae/tap/kantan

# Run at login as a service
brew services start kantan

# Or without the bundled plugins
brew install cmacrae/tap/kantan-without-plugins`,
    note: {
      text: "See the docs for the formulae and the service",
      href: "/docs/getting-started/installation.html#homebrew",
    },
  },
  {
    label: "Script",
    content: `# Install the latest release to ~/.local
curl -fsSL https://kantan.bar/install.sh | sh

# Without the bundled plugins
curl -fsSL https://kantan.bar/install.sh | sh -s -- --without-plugins

# Uninstall
curl -fsSL https://kantan.bar/install.sh | sh -s -- --uninstall`,
    note: {
      text: "See the docs for the script's options",
      href: "/docs/getting-started/installation.html#install-script",
    },
  },
];
