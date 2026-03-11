import AppKit
import Foundation
import Yaml

// MARK: - Structured Command Output Cache

/// Cached JSON output data, keyed by command string to support multiple command modules.
nonisolated(unsafe) private var commandDataCache: [String: CommandOutputData] = [:]
private let commandDataLock = NSLock()

struct CommandOutputData {
  var templateVars: [String: String] = [:]
  var dynamicIcon: String = ""
  var dynamicItems: [[String: Any]] = []
  var hidden: Bool? = nil
  var active: Bool? = nil
  var styleFg: String? = nil
  var styleBg: String? = nil
  var styleIconFg: String? = nil
  var styleTextFg: String? = nil
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

/// Recursively converts a YamlSwift `Yaml` value to a native Swift type
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
  func configuration(from yaml: Yaml, configDir: String?) throws -> ModuleConfiguration {
    return try CommandConfig(yaml: yaml, configDir: configDir)
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

  init(yaml: Yaml, configDir: String? = nil) throws {
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

    // Serialize the optional "settings" block to JSON for passing to plugins.
    if let settingsYaml = yaml["settings"].dictionary, !settingsYaml.isEmpty,
      let native = yamlToNative(.dictionary(settingsYaml)),
      let jsonData = try? JSONSerialization.data(withJSONObject: native),
      let jsonString = String(data: jsonData, encoding: .utf8)
    {
      self.settingsJSON = jsonString
    } else {
      self.settingsJSON = nil
    }
  }

  private static func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  var redrawInterval: TimeInterval { interval }

  func getValue(completion: @escaping @Sendable (String) -> Void) {
    let cmd = self.command
    let path = self.launchPath
    let args = self.launchArgs
    let timeoutInterval = self.timeout
    let mode = self.outputMode
    let settings = self.settingsJSON

    // Capture appearance on main thread before dispatching to background.
    let names: [NSAppearance.Name] = [.darkAqua, .aqua]
    let isDark = NSApp.effectiveAppearance.bestMatch(from: names) == .darkAqua
    let appearance = isDark ? "dark" : "light"

    DispatchQueue.global(qos: .userInitiated).async {
      let result = Self.executeCommand(
        command: cmd,
        launchPath: path,
        launchArgs: args,
        timeout: timeoutInterval,
        settingsJSON: settings,
        appearance: appearance
      )

      if mode == "json" {
        Self.parseJsonOutput(result, cacheKey: cmd, completion: completion)
      } else {
        completion(result)
      }
    }
  }

  func getIcon() -> String {
    if outputMode == "json" {
      let data = getCommandData(for: command)
      if !data.dynamicIcon.isEmpty {
        return data.dynamicIcon
      }
    }
    return ""
  }

  func getTemplateVariables() -> [String: String] {
    if outputMode == "json" {
      return getCommandData(for: command).templateVars
    }
    return [:]
  }

  func shouldDisplay() -> Bool {
    if outputMode == "json" {
      if let hidden = getCommandData(for: command).hidden {
        return !hidden
      }
    }
    return true
  }

  func isActive() -> Bool {
    if outputMode == "json" {
      if let active = getCommandData(for: command).active {
        return active
      }
    }
    return true
  }

  func getDynamicStyle() -> DynamicStyleOverride? {
    guard outputMode == "json" else { return nil }
    let data = getCommandData(for: command)
    guard
      data.styleFg != nil || data.styleBg != nil || data.styleIconFg != nil
        || data.styleTextFg != nil
    else {
      return nil
    }
    return DynamicStyleOverride(
      fg: data.styleFg, bg: data.styleBg,
      iconFg: data.styleIconFg, textFg: data.styleTextFg
    )
  }

  func getMenuDescriptors() -> [MenuItemDescriptor]? {
    guard outputMode == "json" else { return nil }
    let data = getCommandData(for: command)
    guard !data.dynamicItems.isEmpty else { return nil }

    return data.dynamicItems.compactMap { item -> MenuItemDescriptor? in
      if item["separator"] as? Bool == true {
        return .separator()
      }
      if let header = item["header"] as? String {
        return .header(header)
      }
      guard let label = item["label"] as? String else { return nil }
      let iconGlyph = item["icon"] as? String
      let command = item["command"] as? String
      return .item(label, iconGlyph: iconGlyph) {
        guard let command = command, !command.isEmpty else { return }
        runShellCommand(command)
      }
    }
  }

  // MARK: - JSON Parsing

  private static func parseJsonOutput(
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

    var data = CommandOutputData()

    // Extract icon override
    if let icon = json["icon"] as? String {
      data.dynamicIcon = icon
    }

    // Extract template variables
    if let vars = json["variables"] as? [String: String] {
      data.templateVars = vars
    }

    // Extract dynamic menu items
    if let items = json["items"] as? [[String: Any]] {
      data.dynamicItems = items
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
      if let iconStyle = style["icon"] as? [String: String] {
        data.styleIconFg = iconStyle["fg"]
      }
      if let textStyle = style["text"] as? [String: String] {
        data.styleTextFg = textStyle["fg"]
      }
    }

    setCommandData(data, for: cacheKey)

    // Extract display value
    let value = json["value"] as? String ?? raw
    completion(value)
  }

  // MARK: - Command Execution

  private static func executeCommand(
    command: String,
    launchPath: String,
    launchArgs: [String],
    timeout: TimeInterval,
    settingsJSON: String? = nil,
    appearance: String? = nil
  ) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = launchArgs + [command]

    if settingsJSON != nil || appearance != nil {
      var env = ProcessInfo.processInfo.environment
      if let settings = settingsJSON {
        env["KANTAN_SETTINGS"] = settings
      }
      if let appearance = appearance {
        env["KANTAN_APPEARANCE"] = appearance
      }
      process.environment = env
    }

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

    return String(data: outdata, encoding: .utf8)?.trimmingCharacters(in: .newlines) ?? ""
  }
}
