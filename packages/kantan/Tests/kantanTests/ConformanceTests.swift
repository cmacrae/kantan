import Foundation
import Testing

@testable import kantan

// The shared cases in web/fixtures, which the web engine's tests run too:
// each gives an input and the result kantan gives for it, so the engine
// can't drift from kantan without a check failing.

// MARK: - Fixtures

/// The shared cases in `name`.json: from `KANTAN_FIXTURES` when the build
/// sets it, and from the checkout's web/fixtures otherwise.
private func fixtures(_ name: String) throws -> [[String: Any]] {
  let directory =
    ProcessInfo.processInfo.environment["KANTAN_FIXTURES"].map { URL(fileURLWithPath: $0) }
    ?? URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("web/fixtures")
  let data = try Data(contentsOf: directory.appendingPathComponent("\(name).json"))
  return try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
}

/// `value` as JSON text.
private func jsonText(_ value: Any) throws -> String {
  let data = try JSONSerialization.data(
    withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes])
  return String(decoding: data, as: UTF8.self)
}

/// `value`, parsed JSON, as the YAML kantan would read from a file holding it.
private func yaml(_ value: Any) throws -> Yaml {
  try Yaml.load(try jsonText(value))
}

/// How `actual` differs from what a case expects, compared as a subset:
/// every key `expected` has must match, a list must match item for item,
/// and null means the key is absent.
private func mismatches(_ expected: Any, _ actual: Any?, at path: String = "result") -> [String] {
  let shown = actual.flatMap { try? jsonText($0) } ?? "nothing"
  if expected is NSNull {
    return actual == nil || actual is NSNull ? [] : ["\(path) is \(shown), not absent"]
  }
  if let expected = expected as? [Any] {
    guard let actual = actual as? [Any] else { return ["\(path) is \(shown), not a list"] }
    guard actual.count == expected.count else {
      return ["\(path) has \(actual.count) items, not \(expected.count): \(shown)"]
    }
    return zip(expected, actual).enumerated().flatMap {
      mismatches($1.0, $1.1, at: "\(path)[\($0)]")
    }
  }
  if let expected = expected as? [String: Any] {
    guard let actual = actual as? [String: Any] else {
      return ["\(path) is \(shown), not a mapping"]
    }
    return expected.keys.sorted().flatMap {
      mismatches(expected[$0]!, actual[$0], at: "\(path).\($0)")
    }
  }
  let wanted = (try? jsonText(expected)) ?? "\(expected)"
  return (expected as? NSObject) == (actual as? NSObject)
    ? [] : ["\(path) is \(shown), not \(wanted)"]
}

/// A directory for a case's files, removed when `body` returns.
private func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  return try body(directory)
}

/// Writes each of `files`, parsed JSON by filename, into `directory`.
private func write(_ files: [String: Any], into directory: URL, suffix: String = "") throws {
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  for (name, contents) in files {
    try jsonText(contents).write(
      to: directory.appendingPathComponent(name + suffix), atomically: true, encoding: .utf8)
  }
}

// MARK: - Results as the cases write them

/// A colour as the cases write one: `#rrggbb` or `#rrggbbaa`, `label` for
/// the system's text colour, or `clear` for none, which is how anything
/// that isn't a colour draws.
private func caseColor(_ color: StyleColor) -> String {
  switch color {
  case .label: "label"
  case .clear: "clear"
  case .value(let hex): hexColorDigits(hex).map { "#" + $0.lowercased() } ?? "clear"
  }
}

/// A palette as the cases write one.
private func casePalette(_ palette: ThemePalette) -> [String: Any] {
  var result: [String: Any] = ["fg": palette.fg, "bg": palette.bg, "colors": palette.colors]
  result["shape"] = palette.shape
  return result
}

/// A menu row's part as the cases write one. With no icon table, an icon is
/// the name it was given.
private func casePart(_ part: NativeMenuPart) -> [String: Any] {
  switch part {
  case .text(let text, let secondary, let strikethrough):
    ["text": text, "secondary": secondary, "strike": strikethrough]
  case .icon(let name, _):
    ["text": name, "secondary": false, "strike": false]
  }
}

/// A menu row as the cases write one.
private func caseRow(_ row: NativeMenuRow) -> [String: Any] {
  switch row {
  case .row(let label, let detail, let indicator, let command):
    var result: [String: Any] = [
      "type": "row", "label": label.map(casePart), "detail": detail.map(casePart),
    ]
    result["indicator"] = indicator.flatMap(hexColorDigits).map { "#" + $0.lowercased() }
    result["command"] = command
    return result
  case .action(let label, let icon, let command):
    var result: [String: Any] = ["type": "action", "label": label]
    result["iconText"] = icon
    result["command"] = command
    return result
  case .check(let label, let checked, let command, let uncheckedCommand):
    var result: [String: Any] = ["type": "check", "label": label, "checked": checked]
    result["command"] = command
    result["uncheckedCommand"] = uncheckedCommand
    return result
  case .toggle(let label, let on, let command):
    var result: [String: Any] = ["type": "toggle", "label": label, "on": on]
    result["command"] = command
    return result
  case .header(let text):
    return ["type": "header", "text": text]
  case .divider:
    return ["type": "divider"]
  case .text(let text, let bold, let secondary, let strikethrough):
    return [
      "type": "text", "text": text, "bold": bold, "secondary": secondary, "strike": strikethrough,
    ]
  case .progress(let value, _, _):
    return ["type": "progress", "value": value]
  }
}

/// A resolver that resolves theme templates as a module's views do: against
/// `palette`, or leaving them as written without one.
private func viewResolver(
  variables: [String: String], data: [String: [[String: String]]], palette: ThemePalette?
) -> TemplateResolver {
  let resolver = TemplateResolver(variables: variables, data: data)
  resolver.fallbackResolver = { key in
    guard key.hasPrefix("theme("), key.hasSuffix(")") else { return nil }
    return palette.map { resolveThemeTemplate("{\(key)}", palette: $0) } ?? "{\(key)}"
  }
  return resolver
}

// MARK: - Templates

struct TemplateConformanceTests {
  @Test func testTemplatesResolveAsTheSharedCasesExpect() throws {
    for group in try fixtures("templates") {
      let name = group["name"] as? String ?? ""
      let palette = (group["palette"] as? [String: Any]).map {
        ThemePalette(
          fg: $0["fg"] as? String ?? "", bg: $0["bg"] as? String ?? "",
          shape: $0["shape"] as? String, colors: $0["colors"] as? [String: String] ?? [:])
      }
      var resolver = viewResolver(
        variables: group["variables"] as? [String: String] ?? [:],
        data: group["data"] as? [String: [[String: String]]] ?? [:], palette: palette)
      for scope in group["scopes"] as? [[String: String]] ?? [] {
        resolver = resolver.scoped(with: scope)
      }

      for check in try #require(group["checks"] as? [[String: Any]]) {
        let expected = try #require(check["expect"])
        if let template = check["resolve"] as? String {
          #expect(resolver.resolve(template) == expected as? String, "\(name): resolve \(template)")
        } else if let template = check["command"] as? String {
          #expect(
            resolver.resolveCommand(template) == expected as? String,
            "\(name): command \(template)")
        } else if let template = check["bool"] as? String {
          #expect(resolver.resolveBool(template) == expected as? Bool, "\(name): bool \(template)")
        } else if let condition = check["truthy"] as? String {
          #expect(
            dslEvaluateTruthy(condition, resolver: resolver) == expected as? Bool,
            "\(name): truthy \(condition)")
        } else {
          Issue.record("\(name): a check with nothing to resolve")
        }
      }
    }
  }
}

// MARK: - Themes

struct ThemeConformanceTests {
  @Test func testThemesLoadAsTheSharedCasesExpect() throws {
    for theme in try fixtures("themes") {
      let name = theme["name"] as? String ?? ""
      let loaded = try withTemporaryDirectory { directory in
        try write(
          try #require(theme["themes"] as? [String: Any]),
          into: directory.appendingPathComponent("themes"), suffix: ".yaml")
        return loadThemeConfig(
          from: try yaml(try #require(theme["selection"])), configDir: directory.path)
      }
      let actual: Any =
        loaded.map {
          ["light": casePalette($0.lightPalette), "dark": casePalette($0.darkPalette)]
        } ?? NSNull()
      let differences = mismatches(try #require(theme["expect"]), actual)
      #expect(differences.isEmpty, "\(name): \(differences.joined(separator: "; "))")
    }
  }
}

// MARK: - Menus

struct MenuConformanceTests {
  @Test func testViewsMakeTheMenuRowsTheSharedCasesExpect() throws {
    for menu in try fixtures("menus") {
      let name = menu["name"] as? String ?? ""
      let view = try #require(menu["view"])
      let node: ViewNode? =
        menu["source"] as? String == "json"
        ? try? JSONDecoder().decode(ViewNode.self, from: Data(try jsonText(view).utf8))
        : parseViewNodeFromYaml(try yaml(view))

      // Variables and data reach a view through a command's output.
      let (output, _) = CommandConfig.parseOutput(
        ["variables": menu["variables"] ?? [:], "data": menu["data"] ?? [:]], raw: "")
      let actual: [String: Any] =
        node.map {
          let resolver = TemplateResolver(variables: output.templateVars, data: output.data)
          return ["rows": nativeMenuRows(from: $0, resolver: resolver).map(caseRow)]
        } ?? ["rejected": true]
      let differences = mismatches(try #require(menu["expect"]), actual)
      #expect(differences.isEmpty, "\(name): \(differences.joined(separator: "; "))")
    }
  }
}

// MARK: - Bars

/// What a module shows, read as `ModuleViewModel` reads it once the
/// module's value arrives.
private struct ShownState {
  var value = ""
  var icon = ""
  var isActive = true
  var shouldDisplay = true
  var variables: [String: String] = [:]
  var dynamicStyle: DynamicStyleOverride?
  var viewTree: ViewNode?
  var data: [String: [[String: String]]] = [:]
  var segments: [ValueSegment] = []
  var revealsIcon: Bool?
  var backgroundIcon: String?
  var workspace: WorkspaceDisplay?
  var drawerOpen: Bool?
}

/// The moment a clock's sample gives: an ISO 8601 date, or milliseconds
/// since 1970.
private func sampleDate(_ time: Any?) -> Date? {
  if let text = time as? String { return ISO8601DateFormatter().date(from: text) }
  return (time as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
}

/// The state a built-in module shows for `sample`, a reading of the system
/// as the cases write one, or nil for a module of another type.
private func sampledState(of config: ModuleConfiguration, sample: [String: Any]?) -> ShownState? {
  var state = ShownState()
  let flag = { (key: String) in sample?[key] as? Bool ?? false }

  switch config {
  case let power as PowerConfig:
    let status =
      (sample?["level"] as? Int).map {
        BatteryStatus(
          level: $0, isCharging: flag("charging"), isPluggedIn: flag("plugged"),
          isLowPowerMode: flag("lowPowerMode"))
      } ?? .unavailable
    state.value = power.value(for: status)
    state.icon = power.icon(for: status)
    state.dynamicStyle = power.dynamicStyle(for: status)
    state.variables = PowerConfig.templateVariables(for: status)

  case let volume as VolumeConfig:
    let status = VolumeStatus(
      volume: Float(sample?["volume"] as? Double ?? 0), isMuted: flag("muted"),
      deviceName: sample?["device"] as? String ?? "")
    state.icon = volume.icon(for: status)
    state.backgroundIcon = volume.backgroundIcon(for: status)
    state.variables = VolumeConfig.templateVariables(for: status)

  case let wifi as WiFiConfig:
    let status = WiFiStatus(
      rssi: sample?["rssi"] as? Int ?? 0, isConnected: flag("connected"),
      isHotspot: flag("hotspot"))
    state.icon = wifi.icon(for: status)
    state.backgroundIcon = wifi.backgroundIcon(for: status)
    state.variables = WiFiConfig.templateVariables(for: status)

  case let bluetooth as BluetoothConfig:
    let devices = (sample?["devices"] as? [[String: Any]] ?? []).map {
      BluetoothDeviceInfo(
        name: $0["name"] as? String ?? "", address: "",
        isConnected: $0["connected"] as? Bool ?? false)
    }
    let status = BluetoothStatus(
      isPoweredOn: sample?["on"] as? Bool ?? true, pairedDevices: devices)
    state.icon = bluetooth.icon(for: status)
    state.isActive = BluetoothConfig.isActive(for: status)
    state.variables = BluetoothConfig.templateVariables(for: status)

  case let focus as FocusConfig:
    let mode = (sample?["mode"] as? [String: Any]).flatMap { mode in
      (mode["identifier"] as? String).map {
        FocusMode(identifier: $0, name: mode["name"] as? String ?? $0)
      }
    }
    let status = FocusStatus(isActive: sample?["active"] as? Bool ?? (mode != nil), mode: mode)
    state.shouldDisplay = status.isActive
    state.icon = focus.icon(for: status)
    state.dynamicStyle = focus.dynamicStyle(for: status)
    state.variables = FocusConfig.templateVariables(for: status)

  case let waveform as WaveformConfig:
    let silent = !(sample?["levels"] as? [Double] ?? []).contains { $0 > 0 }
    state.shouldDisplay = WaveformConfig.shouldDisplay(
      silent: silent, hidesWhenSilent: waveform.hidesWhenSilent)
    state.variables = WaveformConfig.templateVariables(silent: silent)

  case let drawer as DrawerConfig:
    state.drawerOpen = flag("open")
    state.icon = drawer.icon(open: flag("open"))

  case let clock as ClockConfig:
    let date = sampleDate(sample?["time"]) ?? Date()
    let timezone = clock.timezone ?? sample?["timezone"] as? String
    let locale = (sample?["locale"] as? String).map(Locale.init(identifier:))
    let write = {
      ClockConfig.string(from: date, format: $0, timezone: timezone, locale: locale)
    }
    state.value = write(clock.format)
    state.variables = clock.formats.mapValues(write)

  case let workspace as WorkspaceConfig:
    let spaces = (sample?["workspaces"] as? [[String: Any]] ?? []).enumerated().map {
      position, space -> Workspace in
      let index = space["index"] as? Int ?? position
      return Workspace(
        index: index, label: space["label"] as? String ?? String(index + 1),
        isActive: space["active"] as? Bool ?? false,
        hasWindows: space["hasWindows"] as? Bool ?? false,
        scroll: (space["scroll"] as? [[String: Any]])?.map {
          ScrollWindow(
            id: $0["id"] as? String ?? "", app: $0["app"] as? String ?? "",
            bundleIdentifier: $0["bundleIdentifier"] as? String,
            isSelected: $0["selected"] as? Bool ?? false)
        })
    }
    state.workspace = workspace.display(of: spaces)

  default:
    return nil
  }
  return state
}

/// The state `module` shows for `output`: for a command module, what its
/// command printed, as text or the JSON a plugin's output parses to; for a
/// module reading the system, a sample of what it reads. A module of
/// another type shows its own value.
private func shownState(of module: ModuleConfig, output: Any?) throws -> ShownState {
  var state = ShownState()
  guard let config = module.config else { return state }
  if let sampled = sampledState(of: config, sample: output as? [String: Any]) { return sampled }

  final class Box: @unchecked Sendable { var value = "" }
  let box = Box()
  if let command = config as? CommandConfig {
    let raw = try output.map { try $0 as? String ?? jsonText($0) } ?? ""
    if command.outputMode == "json" {
      CommandConfig.parseJsonOutput(raw, cacheKey: command.cacheKey) { box.value = $0 }
    } else {
      box.value = raw
    }
    state.data = command.getData()
    state.segments = command.getSegments()
    state.revealsIcon = command.revealsIcon()
  } else {
    config.getValue { box.value = $0 }
  }

  state.value = box.value
  state.icon = config.getIcon()
  state.isActive = config.isActive()
  state.shouldDisplay = config.shouldDisplay()
  state.variables = config.getTemplateVariables()
  state.dynamicStyle = config.getDynamicStyle()
  state.viewTree = config.getViewTree()
  return state
}

/// A workspace module's display as the cases write one, coloured and paged
/// as `WorkspaceModuleView` draws it.
private func caseWorkspace(_ module: ModuleConfig, display: WorkspaceDisplay, styles: StyleResolver)
  -> [String: Any]
{
  let fg = styles.textFg(style: module.style, dynamic: nil)
  let segment = { (segment: WorkspaceSegment) -> [String: Any] in
    var result: [String: Any] = [
      "id": segment.id, "name": segment.label, "active": segment.isActive,
      "opacity": segment.isActive ? 1 : 0.4,
    ]
    if !styles.isNative, let color = segment.colorOverride {
      result["color"] = caseColor(.value(styles.resolve(color)))
    } else {
      result["color"] = caseColor(fg)
    }
    switch segment.target {
    case .workspace(let index, let label): result["target"] = ["workspace": index, "label": label]
    case .window(let id): result["target"] = ["window": id]
    case nil: break
    }
    return result
  }

  let overflow = (module.config as? WorkspaceConfig)?.overflow
  let page = display.page(max: overflow?.enabled == true ? overflow?.max : nil)
  let indicator = { (icon: String) -> [String: Any] in
    let own = (styles.isDark ? overflow?.style?.dark : overflow?.style?.light)?.fg
      .map(styles.resolve)
    if let own, !own.hasPrefix("{theme(") {
      return ["name": icon, "color": caseColor(.value(own)), "opacity": 1]
    }
    return ["name": icon, "color": caseColor(fg), "opacity": 0.4]
  }

  var result: [String: Any] = [
    "scroll": display.isScroll, "activates": WorkspaceModuleView.activates(module),
    "segments": page.segments.map(segment), "pips": display.pips.map(segment),
  ]
  result["slot"] = display.slot.map(segment)
  if let overflow, overflow.showIcon {
    result["before"] = page.before ? indicator(overflow.iconLeft) : nil
    result["after"] = page.after ? indicator(overflow.iconRight) : nil
  }
  return result
}

/// A module as the cases write one, drawn as `StandardModuleView` draws it
/// and answering hovers and clicks as `ModuleContainerView` does.
private func caseModule(_ module: ModuleConfig, state: ShownState, styles: StyleResolver)
  -> [String: Any]
{
  var result: [String: Any] = [
    "name": module.name, "type": module.type, "hidden": !state.shouldDisplay,
  ]
  result["open"] = state.drawerOpen
  if let display = state.workspace {
    result["workspace"] = caseWorkspace(module, display: display, styles: styles)
  }
  let hover = module.interaction?.hover
  let hides = { (part: RevealPart) in
    hover?.hides(part, outputRevealsIcon: state.revealsIcon, segments: state.segments) ?? false
  }

  let icon = state.icon.isEmpty ? module.icon : state.icon
  if let icon, !icon.isEmpty, state.workspace == nil {
    var shown: [String: Any] = [
      "name": icon,
      "color": caseColor(styles.iconFg(style: module.style, dynamic: state.dynamicStyle)),
      "opacity": state.isActive ? 1 : 0.4,
    ]
    shown["background"] = state.backgroundIcon.map { ["name": $0] }
    if hides(.icon) { shown["reveal"] = true }
    result["icon"] = shown
  }

  if !state.value.isEmpty {
    let fg = styles.textFg(style: module.style, dynamic: state.dynamicStyle)
    let segments =
      state.segments.isEmpty ? [ValueSegment(text: state.value, fg: nil)] : state.segments
    let hidesText = hides(.text)
    result["text"] = segments.map {
      var segment: [String: Any] = [
        "text": $0.text, "color": caseColor(styles.segmentFg($0.fg) ?? fg),
      ]
      if hidesText || (hover?.type == "reveal" && $0.reveal) { segment["reveal"] = true }
      return segment
    }
  }

  if state.workspace == nil,
    let shape = styles.shape(style: module.style, dynamic: state.dynamicStyle)
  {
    result["shape"] = shape.rawValue
    result["bg"] = caseColor(styles.bg(style: module.style, dynamic: state.dynamicStyle))
  }

  if hover?.type == "reveal" { result["reveal"] = true }
  if hover?.type == "reveal", hover?.persist == true { result["persist"] = true }
  if let hover = module.interaction?.hover, hover.type == "tooltip", hover.viewTree == nil {
    result["tooltip"] = [
      "text": plainTooltipText(
        hover.content ?? "{value}", value: state.value, icon: icon, variables: state.variables)
    ]
  }

  if let click = module.interaction?.click {
    let tree = click.viewTree ?? state.viewTree
    switch click.type {
    case "menu":
      if let tree {
        var variables = state.variables
        variables["value"] = state.value
        variables["icon"] = icon
        let resolver = viewResolver(
          variables: variables, data: state.data, palette: styles.palette)
        var menu: [String: Any] = [
          "type": "menu", "rows": nativeMenuRows(from: tree, resolver: resolver).map(caseRow),
        ]
        menu["fg"] = styles.isNative ? nil : caseColor(styles.barFg)
        result["click"] = menu
      }
    case "popup":
      if tree != nil { result["click"] = ["type": "popup"] }
    case "toggle", "complete":
      if let toggle = (module.config as? CommandConfig)?.toggleCommand, !toggle.isEmpty {
        result["click"] = ["type": "toggle", "command": toggle]
      }
    default:
      result["click"] = ["type": click.type]
    }
  }
  return result
}

/// The bar kantan shows for `document` as the cases write one: its files
/// written out and loaded as kantan loads a config, in the appearance and
/// with the module states `check` names.
private func caseBar(document: [String: Any], check: [String: Any]) throws -> [String: Any] {
  let config = try withTemporaryDirectory { directory in
    let path = directory.appendingPathComponent("config.yaml").path
    try write(["config.yaml": document["config"] ?? [:]], into: directory)
    try write(
      document["modulesDir"] as? [String: Any] ?? [:],
      into: directory.appendingPathComponent("modules.d"))
    try write(
      document["themes"] as? [String: Any] ?? [:],
      into: directory.appendingPathComponent("themes"), suffix: ".yaml")
    switch loadConfigFile(
      at: path, modulesDir: directory.appendingPathComponent("modules.d").path)
    {
    case .success(let config): return config
    case .failure(let error): return Config.loadError(error, path: path)
    }
  }

  let styles = StyleResolver(config: config, isDark: check["dark"] as? Bool ?? false)
  let states = document["states"] as? [String: [[String: Any]]] ?? [:]
  let chosen = check["states"] as? [String: String] ?? [:]

  var placements: [String: [[String: Any]]] = [
    "left": [], "notchleft": [], "notchright": [], "right": [],
  ]
  for module in config.modules {
    guard
      let placement = module.placement.resolve(hasNotch: check["notch"] as? Bool ?? false),
      placements[placement] != nil
    else { continue }
    let moduleStates = states[module.name] ?? []
    let picked =
      moduleStates.first { $0["name"] as? String == chosen[module.name] } ?? moduleStates.first
    placements[placement]?.append(
      caseModule(
        module, state: try shownState(of: module, output: picked?["output"]), styles: styles))
  }

  return [
    "native": styles.isNative,
    "fg": caseColor(styles.barFg),
    "bg": caseColor(styles.barBg),
    "height": config.height,
    "padding": config.padding,
    "iconTextSpacing": config.iconTextSpacing,
    "placements": placements,
  ]
}

struct BarConformanceTests {
  @Test func testDocumentsResolveToTheBarsTheSharedCasesExpect() throws {
    for bar in try fixtures("bars") + fixtures("modules") {
      let name = bar["name"] as? String ?? ""
      let document = try #require(bar["document"] as? [String: Any])
      for check in try #require(bar["checks"] as? [[String: Any]]) {
        let actual = try caseBar(document: document, check: check)
        let differences = mismatches(try #require(check["expect"]), actual)
        #expect(differences.isEmpty, "\(name): \(differences.joined(separator: "; "))")
      }
    }
  }
}
