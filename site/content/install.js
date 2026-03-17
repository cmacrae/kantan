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
    content: `brew tap cmacrae/kantan
brew install kantan
brew services start kantan`,
  },
  {
    label: "Script",
    content: `curl -fsSL https://kantan.dev/install.sh | sh`,
    note: { text: "Coming soon" },
  },
];
