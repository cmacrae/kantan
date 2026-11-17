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

  moduleSchema = ../docs/schemas/module-config.schema.json;

  # The schema of the plugin's settings.
  schema =
    name:
    let
      file = pluginsDir + "/${name}/settings.schema.json";
    in
    if builtins.pathExists file then
      file
    else
      throw "Plugin '${name}' has no settings schema: packages/plugins/${name}/settings.schema.json must describe its settings";

  # The states a plugin's generator prints for a module: the one the yq
  # expression `module` selects from the YAML file `config`. The generator
  # is given the module's settings as kantan gives a plugin its module's.
  # Theme templates in the settings stay as written, for the preview to
  # resolve in either appearance. With `named`, each colour and icon the
  # plugin's schema describes is given as its own name, for the preview to
  # follow the settings a module has.
  statesFor =
    {
      plugin,
      config,
      module ? ".",
      named ? false,
    }:
    pkgs.runCommand "kantan-preview-states-${plugin}.json"
      {
        nativeBuildInputs = [
          pkgs.yq-go
          pkgs.nodejs
        ];
      }
      ''
        KANTAN_SETTINGS=$(yq -o=json -I=0 '${module} | .config.settings // {}' ${config})
        ${lib.optionalString named ''
          KANTAN_SETTINGS=$(node ${assembler}/previews/name-settings.js ${schema plugin} ${moduleSchema} "$KANTAN_SETTINGS")
        ''}
        KANTAN_MODULE_NAME=$(yq '${module} | .name' ${config})
        export KANTAN_SETTINGS KANTAN_MODULE_NAME KANTAN_APPEARANCE=dark TZ=UTC HOME=$TMPDIR
        ${generate plugin} > $out
      '';

  # What a preview is assembled from for a plugin's module: the states by
  # setting name, the states as printed and the plugin's schema.
  generated =
    args:
    lib.concatStringsSep "=" [
      (statesFor (args // { named = true; }))
      (statesFor args)
      (schema args.plugin)
    ];

  themes = pkgs.runCommand "kantan-preview-themes.json" { nativeBuildInputs = [ pkgs.yq-go ]; } ''
    yq -o=json '{"catppuccin": .}' ${themesDir + "/catppuccin.yaml"} > $out
  '';

  # The engine and the scripts that assemble previews with it.
  assembler = pkgs.runCommand "kantan-preview-assembler" { } ''
    mkdir $out
    cp -r ${../web/engine} $out/engine
    cp -r ${../web/builder} $out/builder
    cp -r ${../web/previews} $out/previews
    cp ${../web/package.json} $out/package.json
  '';

  # The Tabler fonts prepared for the web: icons.css holding the fonts or
  # naming their files, and icons.json mapping each icon to its glyph.
  # `icons` are arguments naming the icons to keep.
  iconFonts =
    name: icons:
    pkgs.runCommand "kantan-${name}-icons"
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
          $out ${icons}
      '';

  # The fonts cut down to the icons a file lists, one to a line.
  iconsFor = name: list: iconFonts name "$(cat ${list})";

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
        ${lib.concatMapStrings (name: ''
          yq -o=json ${example name} > ${name}.example.json
        '') plugins.pluginNames}
        node ${assembler}/previews/assemble.js $out ${themes} ${moduleSchema} \
          ${lib.concatMapStringsSep " " (
            name:
            "${name}=${name}.example.json=${
              generated {
                plugin = name;
                config = example name;
              }
            }"
          ) plugins.pluginNames}
      '';

  icons = iconsFor "preview" "${documents}/icons.txt";

  # Every Tabler icon, for a page where any may be picked.
  allIcons = iconFonts "all" "--all";

  # What the builder offers: each bundled plugin's example module with the
  # states its generator printed, by setting name, and the schema of its
  # settings, and the bundled themes.
  catalog = pkgs.runCommand "kantan-preview-catalog.json" { nativeBuildInputs = [ pkgs.jq ]; } ''
    jq -n --slurpfile themes ${themes} --slurpfile plugins ${documents}/plugins.json \
      '{ themes: $themes[0], plugins: $plugins[0] }' > $out
  '';

  # A whole bar's preview: `config` is its config.yaml, `states` a JSON
  # file of what its built-in modules read, and `plugins` names the plugin
  # behind each of its command modules. Gives the bar's `document`, a
  # directory holding document.json and named.json, the same document with
  # its plugins' states by setting name, and its `icons`.
  bar =
    {
      name,
      config,
      states,
      plugins,
    }:
    rec {
      document =
        pkgs.runCommand "kantan-${name}-document"
          {
            nativeBuildInputs = [
              pkgs.nodejs
              pkgs.yq-go
            ];
          }
          ''
            yq -o=json ${config} > config.json
            node ${assembler}/previews/bar.js $out config.json ${themes} ${states} ${moduleSchema} \
              ${lib.concatStringsSep " " (
                lib.mapAttrsToList (
                  module: plugin:
                  "${module}=${
                    generated {
                      inherit plugin config;
                      module = ".modules[] | select(.name == \"${module}\")";
                    }
                  }"
                ) plugins
              )}
          '';
      icons = iconsFor name "${document}/icons.txt";
    };
in
{
  inherit
    documents
    icons
    bar
    allIcons
    catalog
    ;

  # Every state of every preview holds output the plugin output schema
  # accepts, and every plugin's example holds settings its own schema
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
          [ "$(basename "$preview")" = plugins.json ] && continue
          jq -c '.states[][] | .output' "$preview" | while read -r output; do
            echo "$output" > output.json
            check-jsonschema --schemafile ${../docs/schemas/plugin-output.schema.json} output.json \
              || { echo "$preview holds a state that isn't valid plugin output: $output" >&2; exit 1; }
          done
        done
        for plugin in $(jq -r 'keys[]' ${documents}/plugins.json); do
          jq --arg plugin "$plugin" '.[$plugin].settings' ${documents}/plugins.json > settings.schema.json
          jq --arg plugin "$plugin" '.[$plugin].module.config.settings // {}' ${documents}/plugins.json > settings.json
          check-jsonschema --schemafile settings.schema.json settings.json \
            || { echo "$plugin's example holds settings its settings.schema.json rejects" >&2; exit 1; }
        done
        touch $out
      '';
}
