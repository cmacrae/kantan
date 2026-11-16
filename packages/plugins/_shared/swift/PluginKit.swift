import Foundation

// MARK: - JSON View Tree Types

/// A JSON value that can be any type — used to build view trees emitted by plugins.
indirect enum JSONValue: Encodable {
  case string(String)
  case int(Int)
  case double(Double)
  case bool(Bool)
  case array([JSONValue])
  case object([String: JSONValue])
  case null

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let s): try container.encode(s)
    case .int(let i): try container.encode(i)
    case .double(let d): try container.encode(d)
    case .bool(let b): try container.encode(b)
    case .array(let a): try container.encode(a)
    case .object(let o): try container.encode(o)
    case .null: try container.encodeNil()
    }
  }
}

// MARK: - View Tree Builders

func vstack(
  spacing: Double? = nil, padding: JSONValue? = nil, frame: JSONValue? = nil,
  children: [JSONValue]
) -> JSONValue {
  var obj: [String: JSONValue] = ["type": .string("vstack"), "children": .array(children)]
  if let s = spacing { obj["spacing"] = .double(s) }
  if let p = padding { obj["padding"] = p }
  if let f = frame { obj["frame"] = f }
  return .object(obj)
}

func hstack(
  spacing: Double? = nil, padding: JSONValue? = nil, command: String? = nil,
  children: [JSONValue]
) -> JSONValue {
  var obj: [String: JSONValue] = ["type": .string("hstack"), "children": .array(children)]
  if let s = spacing { obj["spacing"] = .double(s) }
  if let p = padding { obj["padding"] = p }
  if let c = command { obj["command"] = .string(c) }
  return .object(obj)
}

func text(
  _ content: String, size: Double? = nil, weight: String? = nil, style: String? = nil,
  color: String? = nil, strikethrough: Bool = false
) -> JSONValue {
  var obj: [String: JSONValue] = ["type": .string("text"), "content": .string(content)]
  if let s = size { obj["size"] = .double(s) }
  if let w = weight { obj["weight"] = .string(w) }
  if let st = style { obj["style"] = .string(st) }
  if let c = color { obj["color"] = .string(c) }
  if strikethrough { obj["strikethrough"] = .bool(true) }
  return .object(obj)
}

func header(_ content: String) -> JSONValue {
  .object(["type": .string("header"), "content": .string(content)])
}

func divider() -> JSONValue {
  .object(["type": .string("divider")])
}

func spacer() -> JSONValue {
  .object(["type": .string("spacer")])
}

func icon(_ name: String, size: Double? = nil, color: String? = nil) -> JSONValue {
  var obj: [String: JSONValue] = ["type": .string("icon"), "name": .string(name)]
  if let s = size { obj["size"] = .double(s) }
  if let c = color { obj["color"] = .string(c) }
  return .object(obj)
}

func action(label: String, icon iconName: String? = nil, command: String? = nil) -> JSONValue {
  var obj: [String: JSONValue] = ["type": .string("action"), "label": .string(label)]
  if let i = iconName { obj["icon"] = .string(i) }
  if let c = command { obj["command"] = .string(c) }
  return .object(obj)
}

func check(label: String, checked: Bool, command: String, uncheckedCommand: String? = nil)
  -> JSONValue
{
  var obj: [String: JSONValue] = [
    "type": .string("check"),
    "label": .string(label),
    "checked": .bool(checked),
    "command": .string(command),
  ]
  if let uc = uncheckedCommand {
    obj["uncheckedCommand"] = .string(uc)
  }
  return .object(obj)
}

func foreach(items: String, child: JSONValue) -> JSONValue {
  .object(["type": .string("foreach"), "items": .string(items), "child": child])
}

func conditional(variable: String, then thenNode: JSONValue) -> JSONValue {
  .object(["type": .string("if"), "condition": .string(variable), "then": thenNode])
}

func group(children: [JSONValue]) -> JSONValue {
  .object(["type": .string("group"), "children": .array(children)])
}

func badge(content: String, color: String? = nil, textColor: String? = nil) -> JSONValue {
  var obj: [String: JSONValue] = ["type": .string("badge"), "content": .string(content)]
  if let c = color { obj["color"] = .string(c) }
  if let tc = textColor { obj["textColor"] = .string(tc) }
  return .object(obj)
}

func rect(
  width: Double? = nil, height: Double? = nil, color: String? = nil,
  cornerRadius: Double? = nil
) -> JSONValue {
  var obj: [String: JSONValue] = ["type": .string("rect")]
  if let w = width { obj["width"] = .double(w) }
  if let h = height { obj["height"] = .double(h) }
  if let c = color { obj["color"] = .string(c) }
  if let cr = cornerRadius { obj["cornerRadius"] = .double(cr) }
  return .object(obj)
}

// MARK: - Plugin Output

/// A part of the module's value with its own colour, which kantan draws in
/// place of the plain value.
struct ValueSegment: Encodable, Equatable {
  let text: String
  /// A hex colour or `{theme(name)}` template, or nil for the module's.
  let fg: String?
}

/// Top-level envelope emitted by command-module plugins.
/// Optional fields are omitted from the output JSON when nil so downstream
/// parsers see the same shape they did before unification.
struct PluginOutput: Encodable {
  let value: String
  let segments: [ValueSegment]?
  let icon: String?
  let hidden: Bool?
  let active: Bool?
  let variables: [String: String]
  let data: [String: [[String: String]]]
  let view: JSONValue?
  let style: JSONValue?

  init(
    value: String,
    segments: [ValueSegment]? = nil,
    icon: String? = nil,
    hidden: Bool? = nil,
    active: Bool? = nil,
    variables: [String: String] = [:],
    data: [String: [[String: String]]] = [:],
    view: JSONValue? = nil,
    style: JSONValue? = nil
  ) {
    self.value = value
    self.segments = segments
    self.icon = icon
    self.hidden = hidden
    self.active = active
    self.variables = variables
    self.data = data
    self.view = view
    self.style = style
  }

  private enum CodingKeys: String, CodingKey {
    case value, segments, icon, hidden, active, variables, data, view, style
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(value, forKey: .value)
    try container.encodeIfPresent(segments, forKey: .segments)
    try container.encodeIfPresent(icon, forKey: .icon)
    try container.encodeIfPresent(hidden, forKey: .hidden)
    try container.encodeIfPresent(active, forKey: .active)
    try container.encode(variables, forKey: .variables)
    try container.encode(data, forKey: .data)
    try container.encodeIfPresent(view, forKey: .view)
    try container.encodeIfPresent(style, forKey: .style)
  }
}

func printJSON(_ output: PluginOutput, pretty: Bool = false) {
  let encoder = JSONEncoder()
  encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
  guard let data = try? encoder.encode(output) else { return }
  print(String(data: data, encoding: .utf8)!)
}

// MARK: - Watch Mode

/// Writes plugin output as a watch process does: a line per output, written
/// at once rather than buffered, skipping output identical to the last line.
@MainActor
final class WatchOutput {
  private let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }()
  private var last: Data?
  private let write: (Data) -> Void

  init(write: @escaping (Data) -> Void = { FileHandle.standardOutput.write($0) }) {
    self.write = write
  }

  func show(_ output: PluginOutput) {
    guard let line = try? encoder.encode(output), line != last else { return }
    last = line
    write(line + Data("\n".utf8))
  }
}

/// Exits once stdin closes, as kantan closes it to stop a watch process.
func exitWhenStdinCloses() {
  DispatchQueue.global().async {
    while !FileHandle.standardInput.availableData.isEmpty {}
    exit(0)
  }
}

/// Writes `output` and waits for kantan to stop the watch process, for a
/// watch process that has nothing to watch; exiting instead would have
/// kantan restart it.
@MainActor
func idleWatch(showing output: PluginOutput) -> Never {
  WatchOutput().show(output)
  while !FileHandle.standardInput.availableData.isEmpty {}
  exit(0)
}

/// The start of the minute after `date`.
func startOfMinute(after date: Date) -> Date {
  let minutes = (date.timeIntervalSinceReferenceDate / 60).rounded(.down)
  return Date(timeIntervalSinceReferenceDate: (minutes + 1) * 60)
}

/// Shows a watch process's output when it may have changed: at the start
/// of every minute, and once a burst of changes has settled.
@MainActor
final class Watch {
  /// How long after a change more changes are awaited before showing the
  /// output, so a burst, such as a sync, shows it once.
  static let settling: TimeInterval = 0.5

  private let render: () -> PluginOutput
  private let output: WatchOutput
  private var changePending = false

  init(output: WatchOutput = WatchOutput(), render: @escaping () -> PluginOutput) {
    self.output = output
    self.render = render
  }

  func show() {
    output.show(render())
  }

  /// Shows the output once `settling` has passed since the first change
  /// not yet shown.
  func changed() {
    guard !changePending else { return }
    changePending = true
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.settling) {
      MainActor.assumeIsolated {
        self.changePending = false
        self.show()
      }
    }
  }

  /// Shows the output now, at the start of every minute and after each
  /// `notification` from `object`, until kantan closes stdin.
  func run(on notification: Notification.Name, from object: AnyObject) -> Never {
    show()
    NotificationCenter.default.addObserver(forName: notification, object: object, queue: .main) {
      _ in
      MainActor.assumeIsolated { self.changed() }
    }
    let minutes = Timer(fire: startOfMinute(after: Date()), interval: 60, repeats: true) { _ in
      MainActor.assumeIsolated { self.show() }
    }
    RunLoop.main.add(minutes, forMode: .common)
    exitWhenStdinCloses()
    RunLoop.main.run()
    exit(0)
  }
}

// MARK: - Settings Loading

/// Returns the module name from KANTAN_MODULE_NAME, falling back to `fallback`.
func moduleName(fallback: String) -> String {
  ProcessInfo.processInfo.environment["KANTAN_MODULE_NAME"] ?? fallback
}

/// Decode the plugin's settings from the `KANTAN_SETTINGS` environment variable.
/// Returns `defaults` when the variable is absent, empty, or fails to decode.
func loadSettings<T: Decodable>(defaults: T) -> T {
  guard let json = ProcessInfo.processInfo.environment["KANTAN_SETTINGS"],
    let data = json.data(using: .utf8)
  else {
    return defaults
  }
  return (try? JSONDecoder().decode(T.self, from: data)) ?? defaults
}

extension KeyedDecodingContainer {
  /// The setting at `key`, or nil when it's missing or of the wrong kind, so
  /// one bad setting takes its default without discarding the others.
  func setting<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
    (try? decodeIfPresent(type, forKey: key)) ?? nil
  }
}

// MARK: - Helpers

/// Single-quote shell escape for safe command embedding.
func shellQuote(_ s: String) -> String {
  "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// Parses a duration string like "10m", "12h", "2d" into seconds.
func parseDuration(_ string: String) -> TimeInterval? {
  let trimmed = string.trimmingCharacters(in: .whitespaces).lowercased()
  guard let suffix = trimmed.last, trimmed.count >= 2,
    let value = Double(trimmed.dropLast()), value > 0
  else { return nil }

  switch suffix {
  case "m": return value * 60
  case "h": return value * 3600
  case "d": return value * 86400
  default: return nil
  }
}

/// Apply template variable substitution to a format string.
/// Supports `{key}` substitution and `{?var:text}` / `{?!var:text}` conditional
/// sections (truthy / falsy respectively). Variables not present in the map
/// resolve to the empty string.
private let conditionalPattern: NSRegularExpression? = try? NSRegularExpression(
  pattern: #"\{\?(!?)(\w+):([^}]*)\}"#, options: [])

func applyFormat(_ format: String, variables: [String: String]) -> String {
  var result = format

  if let conditionalPattern = conditionalPattern {
    let fullRange = NSRange(result.startIndex..., in: result)
    let matches = conditionalPattern.matches(in: result, range: fullRange).reversed()
    for match in matches {
      let negated = Range(match.range(at: 1), in: result).map { !result[$0].isEmpty } ?? false
      let varName = Range(match.range(at: 2), in: result).map { String(result[$0]) } ?? ""
      let body = Range(match.range(at: 3), in: result).map { String(result[$0]) } ?? ""
      let matchRange = Range(match.range, in: result)!

      let isTruthy = !(variables[varName] ?? "").isEmpty
      let shouldInclude = negated ? !isTruthy : isTruthy
      result.replaceSubrange(matchRange, with: shouldInclude ? body : "")
    }
  }

  for (key, value) in variables {
    result = result.replacingOccurrences(of: "{\(key)}", with: value)
  }
  return result
}

/// A plugin's `format` setting: a template for the value, or segments of
/// templates, each with an optional `fg` colour and shown only while its
/// `when` variable is truthy, or falsy as `!name`, the tests `{?name:...}`
/// and `{?!name:...}` make.
enum Format: Decodable, Equatable {
  case template(String)
  case segments([Segment])

  struct Segment: Decodable, Equatable {
    var text: String
    var fg: String?
    var when: String?

    /// Whether the segment shows for `variables`.
    func shows(for variables: [String: String]) -> Bool {
      guard let when else { return true }
      let negated = when.hasPrefix("!")
      let isTruthy = !(variables[String(when.dropFirst(negated ? 1 : 0))] ?? "").isEmpty
      return negated != isTruthy
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let template = try? container.decode(String.self) {
      self = .template(template)
    } else {
      self = .segments(try container.decode([Segment].self))
    }
  }

  /// The value for `variables`, and its coloured segments when the format
  /// has segments; those that come out empty are left out.
  func apply(_ variables: [String: String]) -> (value: String, segments: [ValueSegment]?) {
    switch self {
    case .template(let template):
      return (applyFormat(template, variables: variables), nil)
    case .segments(let segments):
      let shown =
        segments
        .filter { $0.shows(for: variables) }
        .map { ValueSegment(text: applyFormat($0.text, variables: variables), fg: $0.fg) }
        .filter { !$0.text.isEmpty }
      return (shown.map(\.text).joined(), shown)
    }
  }
}
