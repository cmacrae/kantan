{
  pkgs,
  plugins,
  pluginsDir,
  themesDir,
  tabler-icons,
}:
let
  inherit (pkgs) lib;

  generatorDir =
    name:
    let
      dir = pluginsDir + "/${name}/preview";
    in
    if builtins.pathExists dir then
      dir
    else
      throw "Plugin '${name}' has no preview: packages/plugins/${name}/preview must hold its generator";

  # The plugin's sources with its preview generator in place of its entry
  # point, so the generator is built from the plugin's own code.
  generatorSrc =
    name:
    let
      bin = plugins.binName name;
    in
    pkgs.runCommand "${bin}-preview-src" { } (
      ''
        cp -r ${plugins.sourceOf name} $out
        chmod -R u+w $out
      ''
      + {
        "Package.swift" = ''
          rm $out/Sources/${bin}/main.swift
          cp ${generatorDir name}/*.swift $out/Sources/${bin}/
        '';
        "go.mod" = ''
          rm $out/main.go
          cp ${generatorDir name}/*.go $out/
        '';
        "main.sh" = ''
          cp ${generatorDir name}/main.sh $out/preview.sh
        '';
      }
      .${plugins.markerOf name}
    );

  # The command printing the plugin's preview states: its generator, built
  # as the plugin is but without running the plugin's tests again.
  generate =
    name:
    if plugins.markerOf name == "main.sh" then
      "sh ${generatorSrc name}/preview.sh ${generatorSrc name}/main.sh"
    else
      "${
        (plugins.buildPlugin {
          inherit name;
          src = generatorSrc name;
        }).overrideAttrs
          { doCheck = false; }
      }/bin/${plugins.binName name}";

  example = name: pluginsDir + "/${name}/examples/00-${name}.yaml";

  # The states each plugin's generator prints, given the settings of the
  # plugin's example config as kantan gives a plugin its module's. Theme
  # templates in the settings stay as written, for the preview to resolve
  # in either appearance.
  states =
    name:
    pkgs.runCommand "kantan-preview-states-${name}.json" { nativeBuildInputs = [ pkgs.yq-go ]; } ''
      KANTAN_SETTINGS=$(yq -o=json -I=0 '.config.settings // {}' ${example name})
      KANTAN_MODULE_NAME=$(yq '.name' ${example name})
      export KANTAN_SETTINGS KANTAN_MODULE_NAME KANTAN_APPEARANCE=dark TZ=UTC HOME=$TMPDIR
      ${generate name} > $out
    '';

  # Each plugin's preview as a document, <name>.json, drawn in the
  # Catppuccin theme, with the icons they draw listed in icons.txt.
  documents =
    pkgs.runCommand "kantan-previews"
      {
        nativeBuildInputs = [
          pkgs.nodejs
          pkgs.yq-go
        ];
      }
      ''
        yq -o=json '{"catppuccin": .}' ${themesDir + "/catppuccin.yaml"} > themes.json
        ${lib.concatMapStrings (name: ''
          yq -o=json ${example name} > ${name}.example.json
        '') plugins.pluginNames}
        cp -r ${../web/engine} engine
        cp -r ${../web/previews} previews
        cp ${../web/package.json} package.json
        node previews/assemble.js $out themes.json \
          ${lib.concatMapStringsSep " " (
            name: "${name}=${name}.example.json=${states name}"
          ) plugins.pluginNames}
      '';

  # The Tabler fonts cut down to the icons the previews draw: icons.css
  # holding the fonts, and icons.json mapping each icon to its glyph.
  icons =
    pkgs.runCommand "kantan-preview-icons"
      {
        nativeBuildInputs = [
          (pkgs.python3.withPackages (ps: [
            ps.fonttools
            ps.brotli
          ]))
        ];
      }
      ''
        mkdir $out
        # shellcheck disable=SC2046
        python3 ${./preview-icons.py} \
          ${tabler-icons}/share/fonts/tabler-icons.ttf \
          ${tabler-icons}/share/fonts/tabler-icons-filled.ttf \
          $out $(cat ${documents}/icons.txt)
      '';
in
{
  inherit documents icons;

  # Every state of every preview holds output the plugin output schema
  # accepts.
  check =
    pkgs.runCommand "kantan-previews-check"
      {
        nativeBuildInputs = [
          pkgs.jq
          pkgs.check-jsonschema
        ];
      }
      ''
        for preview in ${documents}/*.json; do
          jq -c '.states[][] | .output' "$preview" | while read -r output; do
            echo "$output" > output.json
            check-jsonschema --schemafile ${../docs/schemas/plugin-output.schema.json} output.json \
              || { echo "$preview holds a state that isn't valid plugin output: $output" >&2; exit 1; }
          done
        done
        touch $out
      '';
}
