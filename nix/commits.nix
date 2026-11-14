{ pkgs, cogConfig }:
let
  inherit (pkgs) lib;

  cog = builtins.fromTOML (builtins.readFile cogConfig);

  # Checks the commits in a revision range with `cog check`, then fails when a
  # feat or fix commit changes none of what a release ships: kantan, its
  # bundled plugins and themes, and its icon font, or kantan's sources from
  # before they moved under packages/. Their tests and the plugins' READMEs
  # don't count. A single revision checks every commit before it.
  check = pkgs.writeShellApplication {
    name = "kantan-check-commits";
    runtimeInputs = [
      pkgs.cocogitto
      pkgs.git
      pkgs.gnugrep
    ];
    text = ''
      cd "$(git rev-parse --show-toplevel)"

      # The release guard, over the commits in a range
      guard() {
        local status=0 commit subject files shipped
        for commit in $(git rev-list --no-merges "$1"); do
          subject=$(git log -1 --format=%s "$commit")
          if ! grep -qE '^(feat|fix)(\(|!|:)' <<<"$subject"; then
            continue
          fi
          files=$(git diff-tree --no-commit-id --name-only -r --root "$commit")
          shipped=$(grep -E '^(packages/(kantan|plugins|themes|tabler-icons)/|Sources/|Package\.(swift|resolved)$)' <<<"$files" \
            | grep -vE '(^|/)Tests/|_test\.go$|^packages/plugins/[^/]+/README\.md$' || true)
          if [ -z "$shipped" ]; then
            git log -1 --format='%h %s' "$commit"
            status=1
          fi
        done
        if [ "$status" -ne 0 ]; then
          echo "These feat and fix commits change nothing a release ships. Use site, docs, build, ci, test or chore." >&2
        fi
        return "$status"
      }

      check() {
        if [[ $1 == *..* ]]; then
          cog check --ignore-merge-commits "$1"
        else
          cog check --ignore-merge-commits
        fi
        guard "$1"
      }

      if [ $# -ne 1 ]; then
        echo "usage: kantan-check-commits <revision range>" >&2
        exit 2
      fi

      check "$1"
    '';
  };

  # kantan's module registry, which lists every module type
  modulesSource = ../packages/kantan/Sources/kantan/modules/modules.swift;

  plugins = lib.attrNames (
    lib.filterAttrs (name: type: type == "directory" && name != "_shared") (
      builtins.readDir ../packages/plugins
    )
  );
in
{
  app = {
    type = "app";
    program = lib.getExe check;
  };

  # Runs the check over commits that should pass and commits that should fail.
  test =
    pkgs.runCommand "kantan-check-commits-test"
      {
        nativeBuildInputs = [
          pkgs.git
          check
        ];
      }
      ''
        export HOME=$TMPDIR
        git init -q -b main repo
        cd repo
        git config user.name test
        git config user.email test@example.invalid
        cp ${cogConfig} cog.toml
        git add cog.toml
        git commit -q -m "chore: start"
        base=$(git rev-parse HEAD)

        commit() {
          mkdir -p "$(dirname "$2")"
          echo x >> "$2"
          git add "$2"
          git commit -q -m "$1"
        }

        expect() {
          if kantan-check-commits "$base..HEAD" > /dev/null 2>&1; then result=pass; else result=fail; fi
          if [ "$result" != "$1" ]; then
            echo "expected $1 after: $(git log -1 --format=%s)" >&2
            exit 1
          fi
          git reset -q --hard "$base"
        }

        commit "feat(bar): new" packages/kantan/Sources/kantan/bar.swift
        expect pass
        commit "fix(pomodoro): fixed" packages/plugins/pomodoro/main.go
        expect pass
        commit "feat(workspace)!: breaking" packages/kantan/Sources/kantan/workspace.swift
        expect pass
        commit "fix: before packages/" Sources/kantan/bar.swift
        expect pass
        commit "site: new page" site/index.html
        expect pass
        commit "build(nix): tidy" nix/site.nix
        expect pass
        commit "feat: a landing page" site/index.html
        expect fail
        commit "fix(nix): packaging" nix/homebrew.nix
        expect fail
        commit "fix(bar): tests only" packages/kantan/Tests/kantanTests/bar.swift
        expect fail
        commit "fix(tailscale): readme" packages/plugins/tailscale/README.md
        expect fail
        commit "feat(nonsense): unknown scope" packages/kantan/Sources/kantan/bar.swift
        expect fail
        commit "nonsense: unknown type" packages/kantan/Sources/kantan/bar.swift
        expect fail

        touch $out
      '';

  # Every built-in module and bundled plugin has a commit scope.
  scopes =
    pkgs.runCommand "kantan-commit-scopes"
      {
        scopes = lib.concatLines cog.scopes;
        plugins = lib.concatLines plugins;
      }
      ''
        modules=$(sed -nE 's/^  "([a-z-]+)": [A-Za-z]+ConfigFactory\(\),$/\1/p' ${modulesSource})
        if [ -z "$modules" ]; then
          echo "Found no module types in ${modulesSource}" >&2
          exit 1
        fi
        missing=0
        for name in $modules $plugins; do
          if ! grep -qx "$name" <<<"$scopes"; then
            echo "cog.toml has no scope for $name" >&2
            missing=1
          fi
        done
        [ "$missing" -eq 0 ]
        touch $out
      '';
}
