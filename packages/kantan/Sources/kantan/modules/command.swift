import AppKit
import Foundation

// MARK: - Structured Command Output Cache

/// Cached JSON output data, keyed by command string to support multiple command modules.
nonisolated(unsafe) private var commandDataCache: [String: CommandOutputData] = [:]
private let commandDataLock = NSLock()

/// A part of a module's value with its own colour, from a plugin's
/// `segments` output.
struct ValueSegment: Equatable, Sendable {
  let text: String
  /// A hex colour or `{theme(name)}` template, or nil for the module's.
  let fg: String?
  /// Whether the segment stays hidden until the pointer is over a module
  /// that reveals on hover.
  var reveal = false
}

struct CommandOutputData {
  var templateVars: [String: String] = [:]
  var segments: [ValueSegment] = []
  /// Whether the output marks the icon as hidden until a hover reveals
  /// it, or nil when the output says nothing of what a hover reveals.
  var revealsIcon: Bool?
  var dynamicIcon: String = ""
  var viewTree: ViewNode? = nil
  var data: [String: [[String: String]]] = [:]
  var hidden: Bool? = nil
  var active: Bool? = nil
  var styleFg: String? = nil
  var styleBg: String? = nil
  var styleIconFg: String? = nil
  var styleTextFg: String? = nil
  var styleShape: ShapeOverride? = nil
}

private func getCommandData(for key: String) -> CommandOutputData {
  commandDataLock.lock()
  defer { commandDataLock.unlock() }
  return commandDataCache[key] ?? CommandOutputData()
}

private func setCommandData(_ data: CommandOutputData, for key: String) {
  commandDataLock.lock()
  defer { commandDataLock.unlock() }
  commandDataCache[key] = data
}

// MARK: - Yaml to Native Conversion

/// Recursively converts a `Yaml` value to a native Swift type
/// suitable for `JSONSerialization`.
private func yamlToNative(_ yaml: Yaml) -> Any? {
  switch yaml {
  case .null:
    return nil
  case .bool(let b):
    return b
  case .int(let i):
    return i
  case .double(let d):
    return d
  case .string(let s):
    return s
  case .array(let arr):
    return arr.map { yamlToNative($0) as Any }
  case .dictionary(let dict):
    var result: [String: Any] = [:]
    for (key, value) in dict {
      guard let keyStr = key.string else { continue }
      if let native = yamlToNative(value) {
        result[keyStr] = native
      }
    }
    return result
  }
}

// MARK: - Factory

struct CommandConfigFactory: ModuleConfigurationFactory {
  func configuration(from yaml: Yaml, configDir: String?, theme: ThemeConfig?) throws
    -> ModuleConfiguration
  {
    return try CommandConfig(yaml: yaml, configDir: configDir, theme: theme)
  }
}

// MARK: - Configuration

struct CommandConfig: ModuleConfiguration {
  var type: String { "command" }
  let command: String
  let launchPath: String
  let launchArgs: [String]
  let timeout: TimeInterval
  let outputMode: String  // "text" or "json"
  let interval: TimeInterval  // polling interval; 0 = event-only (no timer)
  let settingsJSON: String?  // Opaque plugin settings serialized as JSON
  let watchCommand: String?  // Long-lived watcher process command
  let toggleCommand: String?  // Command to run on toggle interaction
  let theme: ThemeConfig?  // For resolving {theme(...)} templates in settings
  /// The module's name, given to the commands it runs as KANTAN_MODULE_NAME.
  var moduleName: String?

  init(yaml: Yaml, configDir: String? = nil, theme: ThemeConfig? = nil) throws {
    guard let rawCommand = yaml["command"].string else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: [], debugDescription: "Unable to decode CommandConfig from Yaml"))
    }

    // Resolve relative command paths against the config directory.
    // Commands starting with ./ or ../ are treated as relative paths
    // and wrapped with cd so the shell resolves them correctly.
    if let dir = configDir,
      rawCommand.hasPrefix("./") || rawCommand.hasPrefix("../")
    {
      self.command = "cd \(Self.shellQuote(dir)) && \(rawCommand)"
    } else {
      self.command = rawCommand
    }

    self.launchPath = yaml["launcher"]["path"].string ?? "/bin/sh"
    self.launchArgs = yaml["launcher"]["args"].array?.compactMap { $0.string } ?? ["-c"]
    self.timeout = yaml["timeout"].double ?? 10.0
    self.outputMode = yaml["output"].string ?? "text"
    self.interval = yaml["interval"].double ?? 1.0
    self.watchCommand = yaml["watch"].string
    self.toggleCommand = yaml["toggle"].string

    // Serialize the optional "settings" block to JSON for passing to plugins.
    if let settingsYaml = yaml["settings"].dictionary, !settingsYaml.isEmpty,
      let native = yamlToNative(.dictionary(settingsYaml)),
      JSONSerialization.isValidJSONObject(native),
      let jsonData = try? JSONSerialization.data(withJSONObject: native),
      let jsonString = String(data: jsonData, encoding: .utf8)
    {
      self.settingsJSON = jsonString
    } else {
      self.settingsJSON = nil
    }

    self.theme = theme
  }

  /// Resolve `{theme(...)}` templates in the settings JSON for the given appearance.
  func resolvedSettings(isDark: Bool) -> String? {
    guard let settings = settingsJSON else { return nil }
    guard let theme = theme else { return settings }
    let palette = isDark ? theme.darkPalette : theme.lightPalette
    return resolveAllThemeTemplates(settings, palette: palette)
  }

  private static func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  var redrawInterval: TimeInterval { interval }

  func getWatchCommand() -> String? { watchCommand }

  /// Launches the toggle command and returns immediately; `completion`
  /// runs when it exits, so a slow command (e.g. one waiting on a
  /// permission prompt) never blocks the bar.
  /// The `KANTAN_*` variables this module's toggle and view commands get,
  /// for the current appearance.
  func kantanEnvironment() -> [String: String] {
    let isDark = Self.appearanceIsDark()
    var env = [
      "KANTAN_APPEARANCE": isDark ? "dark" : "light",
      "KANTAN_PID": "\(ProcessInfo.processInfo.processIdentifier)",
    ]
    env["KANTAN_SETTINGS"] = resolvedSettings(isDark: isDark)
    env["KANTAN_MODULE_NAME"] = moduleName
    return env
  }

  func handleToggle(completion: @escaping @Sendable () -> Void) {
    guard let toggle = toggleCommand, !toggle.isEmpty else {
      completion()
      return
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = launchArgs + [toggle]
    process.environment = ProcessInfo.processInfo.environment.merging(kantanEnvironment()) {
      $1
    }
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    process.terminationHandler = { _ in completion() }
    do {
      try process.run()
    } catch {
      completion()
    }
  }

  /// Whether the app's appearance is dark, read on the main thread.
  static func appearanceIsDark() -> Bool {
    let read = {
      MainActor.assumeIsolated {
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      }
    }
    return Thread.isMainThread ? read() : DispatchQueue.main.sync(execute: read)
  }

  func getValue(completion: @escaping @Sendable (String) -> Void) {
    let cmd = self.command
    let path = self.launchPath
    let args = self.launchArgs
    let timeoutInterval = self.timeout
    let mode = self.outputMode
    let moduleName = self.moduleName
    let key = cacheKey

    // Capture appearance before dispatching to background.
    let isDark = Self.appearanceIsDark()
    let settings = resolvedSettings(isDark: isDark)
    let appearance = isDark ? "dark" : "light"

    DispatchQueue.global(qos: .userInitiated).async {
      let result = Self.executeCommand(
        command: cmd,
        launchPath: path,
        launchArgs: args,
        timeout: timeoutInterval,
        settingsJSON: settings,
        appearance: appearance,
        moduleName: moduleName
      )

      if mode == "json" {
        Self.parseJsonOutput(result, cacheKey: key, completion: completion)
      } else {
        completion(result)
      }
    }
  }

  /// Where this module's output is cached: under its name, so modules
  /// running the same command keep their own output.
  /// The key the command's latest output is cached under.
  var cacheKey: String { moduleName ?? command }

  func getIcon() -> String {
    if outputMode == "json" {
      let data = getCommandData(for: cacheKey)
      if !data.dynamicIcon.isEmpty {
        return data.dynamicIcon
      }
    }
    return ""
  }

  func getTemplateVariables() -> [String: String] {
    if outputMode == "json" {
      return getCommandData(for: cacheKey).templateVars
    }
    return [:]
  }

  func shouldDisplay() -> Bool {
    if outputMode == "json" {
      if let hidden = getCommandData(for: cacheKey).hidden {
        return !hidden
      }
    }
    return true
  }

  func isActive() -> Bool {
    if outputMode == "json" {
      if let active = getCommandData(for: cacheKey).active {
        return active
      }
    }
    return true
  }

  func getDynamicStyle() -> DynamicStyleOverride? {
    guard outputMode == "json" else { return nil }
    let data = getCommandData(for: cacheKey)
    guard
      data.styleFg != nil || data.styleBg != nil || data.styleIconFg != nil
        || data.styleTextFg != nil || data.styleShape != nil
    else {
      return nil
    }
    return DynamicStyleOverride(
      fg: data.styleFg, bg: data.styleBg,
      iconFg: data.styleIconFg, textFg: data.styleTextFg, shape: data.styleShape
    )
  }

  func getViewTree() -> ViewNode? {
    guard outputMode == "json" else { return nil }
    return getCommandData(for: cacheKey).viewTree
  }

  func getData() -> [String: [[String: String]]] {
    guard outputMode == "json" else { return [:] }
    return getCommandData(for: cacheKey).data
  }

  /// The coloured parts of the value, or none to show it in one colour.
  func getSegments() -> [ValueSegment] {
    guard outputMode == "json" else { return [] }
    return getCommandData(for: cacheKey).segments
  }

  /// Whether the output marks the icon as hidden until a hover reveals
  /// it, or nil when the output says nothing of what a hover reveals.
  func revealsIcon() -> Bool? {
    guard outputMode == "json" else { return nil }
    return getCommandData(for: cacheKey).revealsIcon
  }

  // MARK: - JSON Parsing

  /// Caches what `raw`, a command's output, parses to under `cacheKey`, and
  /// completes with the value it shows.
  static func parseJsonOutput(
    _ raw: String, cacheKey: String,
    completion: @escaping @Sendable (String) -> Void
  ) {
    guard !raw.isEmpty,
      let jsonData = raw.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
    else {
      // Graceful degradation: if JSON parse fails, treat as plain text
      setCommandData(CommandOutputData(), for: cacheKey)
      completion(raw)
      return
    }

    let (data, value) = parseOutput(json, raw: raw)
    setCommandData(data, for: cacheKey)
    completion(value)
  }

  /// Caches a line a watch process printed as the command's output, when
  /// the module reads JSON and the line is a JSON object, returning the
  /// value to show; nil for any other line.
  func cacheWatchOutput(_ line: Data) -> String? {
    guard outputMode == "json",
      let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
    else { return nil }
    let (data, value) = Self.parseOutput(json, raw: String(decoding: line, as: UTF8.self))
    setCommandData(data, for: cacheKey)
    return value
  }

  /// How deeply a command's `view` may nest objects. Decoding one nested
  /// much deeper overflows the stack of the thread it's decoded on.
  static let maxViewNesting = 64

  /// How many objects deep `value`, parsed JSON, nests, found without
  /// recursion.
  static func nesting(of value: Any) -> Int {
    var deepest = 0
    var pending: [(Any, Int)] = [(value, 0)]
    while let (item, depth) = pending.popLast() {
      if let object = item as? [String: Any] {
        deepest = max(deepest, depth + 1)
        pending += object.values.map { ($0, depth + 1) }
      } else if let array = item as? [Any] {
        pending += array.map { ($0, depth) }
      }
    }
    return deepest
  }

  /// What's wrong with a `view` that failed to decode with `error`, naming
  /// where in the view.
  static func viewProblem(_ error: Error) -> String {
    let context: DecodingError.Context
    switch error {
    case DecodingError.dataCorrupted(let c), DecodingError.keyNotFound(_, let c),
      DecodingError.typeMismatch(_, let c), DecodingError.valueNotFound(_, let c):
      context = c
    default:
      return "\(error)"
    }
    let path = context.codingPath.reduce("view") { path, key in
      key.intValue.map { "\(path)[\($0)]" } ?? "\(path).\(key.stringValue)"
    }
    return "\(path): \(context.debugDescription)"
  }

  /// The data and value a JSON output object carries, the value falling
  /// back to the `raw` output.
  static func parseOutput(_ json: [String: Any], raw: String) -> (CommandOutputData, String) {
    var data = CommandOutputData()

    // Extract icon override
    if let icon = json["icon"] as? String {
      data.dynamicIcon = icon
    }

    // Extract template variables
    if let vars = json["variables"] as? [String: String] {
      data.templateVars = vars
    }

    // Extract the value's coloured parts
    if let segments = json["segments"] as? [[String: Any]] {
      data.segments = segments.compactMap { segment in
        (segment["text"] as? String).map {
          ValueSegment(
            text: $0, fg: segment["fg"] as? String, reveal: segment["reveal"] as? Bool ?? false)
        }
      }
    }

    // Extract the parts a hover reveals
    if let reveal = json["reveal"] as? [String] {
      data.revealsIcon = reveal.contains("icon")
    }

    // Extract view tree (DSL)
    if let viewObj = json["view"] {
      if Self.nesting(of: viewObj) > Self.maxViewNesting {
        print("Ignoring a command's view: nested deeper than \(Self.maxViewNesting) objects")
      } else if let viewData = try? JSONSerialization.data(withJSONObject: viewObj) {
        do {
          data.viewTree = try JSONDecoder().decode(ViewNode.self, from: viewData)
        } catch {
          print("Ignoring a command's view: \(viewProblem(error))")
        }
      }
    }

    // Extract data collections for foreach iteration
    if let dataObj = json["data"] as? [String: [[String: Any]]] {
      var result: [String: [[String: String]]] = [:]
      for (key, array) in dataObj {
        result[key] = array.map { dict in
          var stringDict: [String: String] = [:]
          // A null field is left out, so it reads as missing.
          for (k, v) in dict where !(v is NSNull) {
            stringDict[k] = "\(v)"
          }
          return stringDict
        }
      }
      data.data = result
    }

    // Extract visibility and active state
    if let hidden = json["hidden"] as? Bool {
      data.hidden = hidden
    }
    if let active = json["active"] as? Bool {
      data.active = active
    }

    // Extract dynamic style overrides
    if let style = json["style"] as? [String: Any] {
      data.styleFg = style["fg"] as? String
      data.styleBg = style["bg"] as? String
      data.styleShape = (style["shape"] as? String).flatMap(ShapeOverride.init)
      if let iconStyle = style["icon"] as? [String: String] {
        data.styleIconFg = iconStyle["fg"]
      }
      if let textStyle = style["text"] as? [String: String] {
        data.styleTextFg = textStyle["fg"]
      }
    }

    return (data, json["value"] as? String ?? raw)
  }

  // MARK: - Command Execution

  private static func executeCommand(
    command: String,
    launchPath: String,
    launchArgs: [String],
    timeout: TimeInterval,
    settingsJSON: String? = nil,
    appearance: String? = nil,
    moduleName: String? = nil
  ) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = launchArgs + [command]

    var env = ProcessInfo.processInfo.environment
    if let settings = settingsJSON {
      env["KANTAN_SETTINGS"] = settings
    }
    if let appearance = appearance {
      env["KANTAN_APPEARANCE"] = appearance
    }
    if let moduleName = moduleName {
      env["KANTAN_MODULE_NAME"] = moduleName
    }
    env["KANTAN_PID"] = "\(ProcessInfo.processInfo.processIdentifier)"
    process.environment = env

    let stdoutPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
    } catch {
      return ""
    }

    let timeoutWorkItem = DispatchWorkItem {
      if process.isRunning {
        process.terminate()
      }
    }
    DispatchQueue.global().asyncAfter(
      deadline: .now() + timeout,
      execute: timeoutWorkItem
    )

    let outdata = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    timeoutWorkItem.cancel()

    guard process.terminationStatus == 0 else {
      return ""
    }

    // Bytes that aren't UTF-8 become U+FFFD, as for a watch's output.
    return String(decoding: outdata, as: UTF8.self).trimmingCharacters(in: .newlines)
  }
}
