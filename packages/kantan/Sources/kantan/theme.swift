import Foundation

// MARK: - Theme Types

/// A single colour palette: default fg/bg plus named colours.
struct ThemePalette: Codable, Sendable {
  let fg: String
  let bg: String
  let shape: String?
  let colors: [String: String]
}

/// A loaded theme with palettes for each appearance mode.
/// When the source theme has no light/dark distinction, both
/// palettes contain the same values.
struct ThemeConfig: Codable, Sendable {
  let lightPalette: ThemePalette
  let darkPalette: ThemePalette
}

// MARK: - Theme Reference

/// A parsed reference to a theme, optionally with a flavour.
/// e.g. "catppuccin" → (name: "catppuccin", flavour: nil)
///      "catppuccin[mocha]" → (name: "catppuccin", flavour: "mocha")
private struct ThemeRef {
  let name: String
  let flavour: String?
}

private func parseThemeRef(_ raw: String) -> ThemeRef {
  guard let bracketStart = raw.firstIndex(of: "["),
    let bracketEnd = raw.lastIndex(of: "]"),
    bracketEnd > bracketStart
  else {
    return ThemeRef(name: raw.trimmingCharacters(in: .whitespaces), flavour: nil)
  }
  let name = String(raw[raw.startIndex..<bracketStart]).trimmingCharacters(in: .whitespaces)
  let flavour = String(raw[raw.index(after: bracketStart)..<bracketEnd]).trimmingCharacters(
    in: .whitespaces)
  return ThemeRef(name: name, flavour: flavour.isEmpty ? nil : flavour)
}

// MARK: - Theme Selection

/// Parsed user config for the `theme:` key.
private enum ThemeSelection {
  case uniform(ThemeRef)
  case perMode(light: ThemeRef, dark: ThemeRef)
}

private func parseThemeSelection(from yaml: Yaml) -> ThemeSelection? {
  if let str = yaml.string {
    return .uniform(parseThemeRef(str))
  }
  if yaml.dictionary != nil {
    guard let lightStr = yaml["light"].string,
      let darkStr = yaml["dark"].string
    else {
      print("Theme map requires both 'light' and 'dark' keys")
      return nil
    }
    return .perMode(light: parseThemeRef(lightStr), dark: parseThemeRef(darkStr))
  }
  return nil
}

// MARK: - Theme File Resolution

/// Resolves the themes directory. Priority: --themes-dir flag, then <prefix>/share/themes/.
func bundledThemesDirectory() -> URL? {
  if let explicit = Kantan.themesDirPath {
    let url = URL(fileURLWithPath: explicit)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return url
  }
  guard let prefix = bundledPrefix() else { return nil }
  let themesDir = prefix.appendingPathComponent("share/themes")
  guard FileManager.default.fileExists(atPath: themesDir.path) else { return nil }
  return themesDir
}

/// Search for a theme file or directory by name using the priority chain:
/// 1. <config-dir>/themes/<name>.yaml
/// 2. <config-dir>/themes/<name>/
/// 3. $XDG_CONFIG_HOME/kantan/themes/<name>.yaml
/// 4. $XDG_CONFIG_HOME/kantan/themes/<name>/
/// 5. <prefix>/share/themes/<name>.yaml (bundled)
/// 6. <prefix>/share/themes/<name>/ (bundled directory)
private func findThemeLocation(name: String, configDir: String?) -> URL? {
  let fm = FileManager.default
  var searchPaths: [URL] = []

  func addPaths(base: URL) {
    searchPaths.append(base.appendingPathComponent("\(name).yaml"))
    searchPaths.append(base.appendingPathComponent(name))
  }

  if let configDir = configDir {
    addPaths(base: URL(fileURLWithPath: configDir).appendingPathComponent("themes"))
  }

  let xdgBase =
    ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
    ?? ("~/.config" as NSString).expandingTildeInPath
  addPaths(base: URL(fileURLWithPath: xdgBase).appendingPathComponent("kantan/themes"))

  if let bundled = bundledThemesDirectory() {
    addPaths(base: bundled)
  }

  for url in searchPaths {
    if fm.fileExists(atPath: url.path) {
      return url
    }
  }

  return nil
}

// MARK: - Theme Loading (Public Entry Point)

/// Load a theme from the `theme:` YAML config value.
/// `configDir` is the directory containing the user's config file.
func loadThemeConfig(from yaml: Yaml, configDir: String?) -> ThemeConfig? {
  guard let selection = parseThemeSelection(from: yaml) else { return nil }

  switch selection {
  case .uniform(let ref):
    return loadUniformTheme(ref: ref, configDir: configDir)

  case .perMode(let lightRef, let darkRef):
    guard let lightPalette = loadPaletteForMode(ref: lightRef, mode: "light", configDir: configDir),
      let darkPalette = loadPaletteForMode(ref: darkRef, mode: "dark", configDir: configDir)
    else { return nil }
    return ThemeConfig(lightPalette: lightPalette, darkPalette: darkPalette)
  }
}

// MARK: - Uniform Theme Loading

private func loadUniformTheme(ref: ThemeRef, configDir: String?) -> ThemeConfig? {
  guard let url = findThemeLocation(name: ref.name, configDir: configDir) else {
    print("Theme not found: \(ref.name)")
    return nil
  }

  var isDir: ObjCBool = false
  FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

  if isDir.boolValue {
    return loadDirectoryTheme(url, ref: ref)
  }

  guard let yaml = loadThemeYaml(from: url) else { return nil }

  // Detect format: flavoured → mode-aware → single palette
  if yaml["flavours"].dictionary != nil {
    return loadFlavouredTheme(yaml, ref: ref)
  } else if yaml["light"].dictionary != nil || yaml["dark"].dictionary != nil {
    return loadModeAwareTheme(yaml)
  } else if let palette = parsePalette(from: yaml) {
    return ThemeConfig(lightPalette: palette, darkPalette: palette)
  }

  print("Invalid theme format: \(url.path)")
  return nil
}

// MARK: - Per-Mode Palette Loading

/// Load a single palette for one appearance mode.
/// Used when the user specifies different themes/flavours for light vs dark.
private func loadPaletteForMode(ref: ThemeRef, mode: String, configDir: String?) -> ThemePalette? {
  guard let url = findThemeLocation(name: ref.name, configDir: configDir) else {
    print("Theme not found: \(ref.name)")
    return nil
  }

  var isDir: ObjCBool = false
  FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

  if isDir.boolValue {
    if let flavour = ref.flavour {
      return loadFlavourFile(themeDir: url, flavour: flavour)
    }
    if let defaultFlavour = loadDirectoryDefault(themeDir: url, mode: mode) {
      return loadFlavourFile(themeDir: url, flavour: defaultFlavour)
    }
    print("Directory theme \(ref.name) requires flavour selection")
    return nil
  }

  guard let yaml = loadThemeYaml(from: url) else { return nil }

  if yaml["flavours"].dictionary != nil {
    if let flavour = ref.flavour {
      return parsePalette(from: yaml["flavours"][.string(flavour)])
    }
    if let defaultFlavour = yaml["defaults"][.string(mode)].string {
      return parsePalette(from: yaml["flavours"][.string(defaultFlavour)])
    }
    print("Flavoured theme \(ref.name) requires flavour selection")
    return nil
  } else if yaml["light"].dictionary != nil || yaml["dark"].dictionary != nil {
    // Mode-aware: return the palette for the requested mode
    return parsePalette(from: yaml[.string(mode)])
  } else {
    // Single palette: same for both modes
    return parsePalette(from: yaml)
  }
}

// MARK: - Flavoured Theme Loading

private func loadFlavouredTheme(_ yaml: Yaml, ref: ThemeRef) -> ThemeConfig? {
  if let flavour = ref.flavour {
    // Explicit flavour: same palette for both modes
    guard let palette = parsePalette(from: yaml["flavours"][.string(flavour)]) else {
      print("Flavour '\(flavour)' not found in theme")
      return nil
    }
    return ThemeConfig(lightPalette: palette, darkPalette: palette)
  }

  // Use defaults
  guard let lightFlavour = yaml["defaults"]["light"].string,
    let darkFlavour = yaml["defaults"]["dark"].string
  else {
    print("Flavoured theme requires flavour selection or defaults")
    return nil
  }

  guard let lightPalette = parsePalette(from: yaml["flavours"][.string(lightFlavour)]) else {
    print("Default light flavour '\(lightFlavour)' not found")
    return nil
  }
  guard let darkPalette = parsePalette(from: yaml["flavours"][.string(darkFlavour)]) else {
    print("Default dark flavour '\(darkFlavour)' not found")
    return nil
  }

  return ThemeConfig(lightPalette: lightPalette, darkPalette: darkPalette)
}

// MARK: - Mode-Aware Theme Loading

private func loadModeAwareTheme(_ yaml: Yaml) -> ThemeConfig? {
  let lightYaml = yaml["light"]
  let darkYaml = yaml["dark"]

  // Fall back to the other mode if one is missing
  guard let lightPalette = parsePalette(from: lightYaml) ?? parsePalette(from: darkYaml),
    let darkPalette = parsePalette(from: darkYaml) ?? parsePalette(from: lightYaml)
  else {
    print("Mode-aware theme must have at least one of light/dark with fg and bg")
    return nil
  }

  return ThemeConfig(lightPalette: lightPalette, darkPalette: darkPalette)
}

// MARK: - Directory Theme Loading

private func loadDirectoryTheme(_ themeDir: URL, ref: ThemeRef) -> ThemeConfig? {
  if let flavour = ref.flavour {
    guard let palette = loadFlavourFile(themeDir: themeDir, flavour: flavour) else { return nil }
    return ThemeConfig(lightPalette: palette, darkPalette: palette)
  }

  // Check defaults
  guard let lightFlavour = loadDirectoryDefault(themeDir: themeDir, mode: "light"),
    let darkFlavour = loadDirectoryDefault(themeDir: themeDir, mode: "dark")
  else {
    print(
      "Theme directory \(themeDir.lastPathComponent) requires flavour selection or defaults.yaml")
    return nil
  }

  guard let lightPalette = loadFlavourFile(themeDir: themeDir, flavour: lightFlavour),
    let darkPalette = loadFlavourFile(themeDir: themeDir, flavour: darkFlavour)
  else { return nil }

  return ThemeConfig(lightPalette: lightPalette, darkPalette: darkPalette)
}

private func loadFlavourFile(themeDir: URL, flavour: String) -> ThemePalette? {
  let url = themeDir.appendingPathComponent("\(flavour).yaml")
  guard let yaml = loadThemeYaml(from: url) else {
    print("Flavour file not found: \(url.path)")
    return nil
  }
  return parsePalette(from: yaml)
}

private func loadDirectoryDefault(themeDir: URL, mode: String) -> String? {
  let defaultsURL = themeDir.appendingPathComponent("defaults.yaml")
  guard let yaml = loadThemeYaml(from: defaultsURL) else { return nil }
  return yaml[.string(mode)].string
}

// MARK: - Palette Parsing

private func parsePalette(from yaml: Yaml) -> ThemePalette? {
  guard let fg = yaml["fg"].string,
    let bg = yaml["bg"].string
  else { return nil }

  let shape = yaml["shape"].string

  var colors: [String: String] = [:]
  if let colorsDict = yaml["colors"].dictionary {
    for (key, value) in colorsDict {
      if let k = key.string, let v = value.string {
        colors[k] = v
      }
    }
  }

  return ThemePalette(fg: fg, bg: bg, shape: shape, colors: colors)
}

// MARK: - Helpers

private func loadThemeYaml(from url: URL) -> Yaml? {
  guard let content = try? String(contentsOf: url, encoding: .utf8) else {
    return nil
  }
  do {
    return try Yaml.load(content)
  } catch {
    print("Failed to parse theme YAML: \(url.path) — \(error)")
    return nil
  }
}

// MARK: - Template Resolution

/// Resolve a `{theme(colorName)}` template string against a palette.
/// Returns the hex colour if the template matches and the colour exists,
/// or the original string if it's not a template or the colour isn't found.
func resolveThemeTemplate(_ value: String, palette: ThemePalette) -> String {
  guard value.hasPrefix("{theme(") && value.hasSuffix(")}") else { return value }
  let start = value.index(value.startIndex, offsetBy: 7)  // past "{theme("
  let end = value.index(value.endIndex, offsetBy: -2)  // before ")}"
  guard start < end else { return value }
  let name = String(value[start..<end])

  // Special names for the palette's own defaults
  if name == "fg" { return palette.fg }
  if name == "bg" { return palette.bg }
  if name == "shape", let shape = palette.shape { return shape }

  // Look up in the colour map
  return palette.colors[name] ?? value
}

/// Resolve all `{theme(colorName)}` templates embedded within an arbitrary string.
/// Unlike `resolveThemeTemplate` which only matches strings that are entirely a template,
/// this scans for all occurrences and replaces them in-place. Useful for resolving
/// templates within a JSON settings string before passing to plugins.
func resolveAllThemeTemplates(_ input: String, palette: ThemePalette) -> String {
  var result = input
  while let startRange = result.range(of: "{theme(") {
    let afterOpen = startRange.upperBound
    guard let closeRange = result[afterOpen...].range(of: ")}") else { break }
    let name = String(result[afterOpen..<closeRange.lowerBound])
    let fullRange = startRange.lowerBound..<closeRange.upperBound

    let resolved: String
    if name == "fg" {
      resolved = palette.fg
    } else if name == "bg" {
      resolved = palette.bg
    } else if name == "shape", let shape = palette.shape {
      resolved = shape
    } else {
      resolved = palette.colors[name] ?? String(result[fullRange])
    }

    if resolved == String(result[fullRange]) {
      // Unresolved template — skip past it to avoid infinite loop
      break
    }
    result.replaceSubrange(fullRange, with: resolved)
  }
  return result
}
