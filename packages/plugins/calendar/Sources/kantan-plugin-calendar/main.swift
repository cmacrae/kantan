import EventKit
import Foundation

// MARK: - Settings

struct CalendarFilter: Decodable {
  var include: [String]?
  var exclude: [String]?
}

/// Icon configuration for the calendar plugin.
/// Values are icon names resolved by kantan's bundled icon font system
/// (e.g. "calendar-event-filled"). Raw Unicode glyphs are also accepted.
struct IconConfig: Decodable {
  var icon: String
  var action: String

  static let defaults = IconConfig(
    icon: "calendar-event-filled",
    action: "calendar-event-filled"
  )

  private enum CodingKeys: String, CodingKey {
    case icon, action
  }

  init(icon: String, action: String) {
    self.icon = icon
    self.action = action
  }

  init(from decoder: Decoder) throws {
    let d = Self.defaults
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? d.icon
    self.action = try container.decodeIfPresent(String.self, forKey: .action) ?? d.action
  }
}

struct Settings: Decodable {
  var format: String
  var upcoming: String?
  var calendars: CalendarFilter?
  var icons: IconConfig

  private enum CodingKeys: String, CodingKey {
    case format, upcoming, calendars, icons
  }

  init() {
    self.format = "{next_title} in {next_countdown}"
    self.upcoming = nil
    self.calendars = nil
    self.icons = .defaults
  }

  init(from decoder: Decoder) throws {
    let defaults = Settings()
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.format = try container.decodeIfPresent(String.self, forKey: .format) ?? defaults.format
    self.upcoming = try container.decodeIfPresent(String.self, forKey: .upcoming)
    self.icons = try container.decodeIfPresent(IconConfig.self, forKey: .icons) ?? defaults.icons

    // calendars can be either an object with include/exclude or a simple string array (include shorthand)
    if let filter = try? container.decodeIfPresent(CalendarFilter.self, forKey: .calendars) {
      self.calendars = filter
    } else if let names = try? container.decodeIfPresent([String].self, forKey: .calendars) {
      self.calendars = CalendarFilter(include: names, exclude: nil)
    } else {
      self.calendars = nil
    }
  }

  /// Window for bar visibility. nil means always show when there are events today.
  var upcomingInterval: TimeInterval? {
    guard let upcoming else { return nil }
    return parseDuration(upcoming)
  }
}

func moduleName() -> String {
  ProcessInfo.processInfo.environment["KANTAN_MODULE_NAME"] ?? "calendar"
}

func loadSettings() -> Settings {
  guard let json = ProcessInfo.processInfo.environment["KANTAN_SETTINGS"],
    let data = json.data(using: .utf8)
  else {
    return Settings()
  }
  return (try? JSONDecoder().decode(Settings.self, from: data)) ?? Settings()
}

// MARK: - Duration Parsing

func parseDuration(_ string: String) -> TimeInterval? {
  let trimmed = string.trimmingCharacters(in: .whitespaces).lowercased()
  guard trimmed.count >= 2 else { return nil }

  let suffix = trimmed.last!
  guard let value = Double(trimmed.dropLast()), value > 0 else { return nil }

  switch suffix {
  case "m": return value * 60
  case "h": return value * 3600
  case "d": return value * 86400
  default: return nil
  }
}

// MARK: - JSON View Tree Types

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
  color: String? = nil
) -> JSONValue {
  var obj: [String: JSONValue] = ["type": .string("text"), "content": .string(content)]
  if let s = size { obj["size"] = .double(s) }
  if let w = weight { obj["weight"] = .string(w) }
  if let st = style { obj["style"] = .string(st) }
  if let c = color { obj["color"] = .string(c) }
  return .object(obj)
}

func textNode(
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

func action(label: String, icon: String? = nil, command: String? = nil) -> JSONValue {
  var obj: [String: JSONValue] = ["type": .string("action"), "label": .string(label)]
  if let i = icon { obj["icon"] = .string(i) }
  if let c = command { obj["command"] = .string(c) }
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

func badge(content: String, color: String? = nil, textColor: String? = nil) -> JSONValue {
  var obj: [String: JSONValue] = ["type": .string("badge"), "content": .string(content)]
  if let c = color { obj["color"] = .string(c) }
  if let tc = textColor { obj["textColor"] = .string(tc) }
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

// MARK: - JSON Output

struct PluginOutput: Encodable {
  let value: String
  let icon: String?
  let hidden: Bool
  let variables: [String: String]
  let data: [String: [[String: String]]]
  let view: JSONValue
}

func printJSON(_ output: PluginOutput) {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  guard let data = try? encoder.encode(output) else { return }
  print(String(data: data, encoding: .utf8)!)
}

// MARK: - Helpers

func shellQuote(_ s: String) -> String {
  "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

func applyFormat(_ format: String, variables: [String: String]) -> String {
  var result = format
  for (key, value) in variables {
    result = result.replacingOccurrences(of: "{\(key)}", with: value)
  }
  return result
}

// MARK: - EventKit Access

func ensureAccess(store: EKEventStore) -> Bool {
  switch EKEventStore.authorizationStatus(for: .event) {
  case .fullAccess, .authorized:
    return true
  case .notDetermined:
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var granted = false
    store.requestFullAccessToEvents { result, error in
      if let error {
        fputs("Error requesting calendar access: \(error)\n", stderr)
      }
      granted = result
      semaphore.signal()
    }
    semaphore.wait()
    return granted
  case .restricted, .denied, .writeOnly:
    return false
  @unknown default:
    return false
  }
}

// MARK: - Calendar Filtering

func filteredCalendars(store: EKEventStore, settings: Settings) -> [EKCalendar] {
  let all = store.calendars(for: .event)

  guard let filter = settings.calendars else {
    return all
  }

  if let include = filter.include, !include.isEmpty {
    let names = Set(include)
    return all.filter { names.contains($0.title) }
  }

  if let exclude = filter.exclude, !exclude.isEmpty {
    let names = Set(exclude)
    return all.filter { !names.contains($0.title) }
  }

  return all
}

// MARK: - Event Fetching

struct CalendarEvent {
  let title: String
  let startDate: Date
  let endDate: Date
  let isAllDay: Bool
  let calendarColor: String
  let calendarName: String
}

func hexColor(from cgColor: CGColor) -> String {
  guard
    let components = cgColor.converted(
      to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil
    )?.components, components.count >= 3
  else {
    return "#888888"
  }
  let r = Int(components[0] * 255)
  let g = Int(components[1] * 255)
  let b = Int(components[2] * 255)
  return String(format: "#%02X%02X%02X", r, g, b)
}

func fetchEvents(store: EKEventStore, calendars: [EKCalendar], from start: Date, to end: Date)
  -> [CalendarEvent]
{
  let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
  let events = store.events(matching: predicate)

  return events.map { event in
    CalendarEvent(
      title: event.title ?? "Untitled",
      startDate: event.startDate,
      endDate: event.endDate,
      isAllDay: event.isAllDay,
      calendarColor: hexColor(from: event.calendar.cgColor),
      calendarName: event.calendar.title
    )
  }.sorted { a, b in
    if a.isAllDay != b.isAllDay { return a.isAllDay }
    return a.startDate < b.startDate
  }
}

// MARK: - Time Formatting

func formatTime(_ date: Date) -> String {
  let formatter = DateFormatter()
  formatter.dateFormat = "HH:mm"
  return formatter.string(from: date)
}

func formatTimeRange(_ start: Date, _ end: Date) -> String {
  "\(formatTime(start)) – \(formatTime(end))"
}

func formatCountdown(from now: Date, to target: Date) -> String {
  let interval = target.timeIntervalSince(now)

  if interval <= 0 {
    return "now"
  }

  let totalMinutes = Int(interval / 60)

  if totalMinutes < 1 {
    return "<1m"
  }

  if totalMinutes < 60 {
    return "\(totalMinutes)m"
  }

  let hours = totalMinutes / 60
  let minutes = totalMinutes % 60

  if minutes == 0 {
    return "\(hours)h"
  }
  return "\(hours)h \(minutes)m"
}

func isToday(_ date: Date) -> Bool {
  Calendar.current.isDateInToday(date)
}

func isTomorrow(_ date: Date) -> Bool {
  Calendar.current.isDateInTomorrow(date)
}

// MARK: - Watch Mode

func watchMode() -> Int32 {
  let store = EKEventStore()
  guard ensureAccess(store: store) else {
    fputs("No access to calendar events\n", stderr)
    return 1
  }

  let name = moduleName()
  let triggerCmd = "kantan trigger \(shellQuote(name)) refresh"

  // Watch for EKEventStore changes
  NotificationCenter.default.addObserver(
    forName: .EKEventStoreChanged,
    object: store,
    queue: nil
  ) { _ in
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", triggerCmd]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
  }

  // 60-second timer for countdown updates
  let timer = Timer(timeInterval: 60.0, repeats: true) { _ in
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", triggerCmd]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
  }
  RunLoop.main.add(timer, forMode: .common)

  // Run until stdin closes
  DispatchQueue.global().async {
    while true {
      let data = FileHandle.standardInput.availableData
      if data.isEmpty {
        exit(0)
      }
    }
  }

  RunLoop.main.run()
  return 0
}

// MARK: - Default Mode

func defaultMode() -> Int32 {
  let settings = loadSettings()
  let store = EKEventStore()

  guard ensureAccess(store: store) else {
    let output = PluginOutput(
      value: "", icon: nil, hidden: true, variables: [:], data: [:],
      view: vstack(children: []))
    printJSON(output)
    return 0
  }

  let calendars = filteredCalendars(store: store, settings: settings)
  guard !calendars.isEmpty else {
    let output = PluginOutput(
      value: "No calendars", icon: nil, hidden: true, variables: [:], data: [:],
      view: vstack(children: [text("No calendars found", style: "secondary")]))
    printJSON(output)
    return 0
  }

  let now = Date()
  let todayStart = Calendar.current.startOfDay(for: now)
  let tomorrowStart = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)!
  let tomorrowEnd = Calendar.current.date(byAdding: .day, value: 2, to: todayStart)!

  // Fetch today's and tomorrow's events
  let allEvents = fetchEvents(
    store: store, calendars: calendars, from: todayStart, to: tomorrowEnd)

  // Partition into today/tomorrow, all-day/timed
  var todayAllDay: [CalendarEvent] = []
  var todayTimed: [CalendarEvent] = []
  var tomorrowAllDay: [CalendarEvent] = []
  var tomorrowTimed: [CalendarEvent] = []

  for event in allEvents {
    if event.isAllDay {
      // All-day events: assign to the day they start on
      if event.startDate < tomorrowStart {
        todayAllDay.append(event)
      } else {
        tomorrowAllDay.append(event)
      }
    } else if event.startDate < tomorrowStart {
      // Timed event starting today (or ongoing from today)
      todayTimed.append(event)
    } else {
      // Tomorrow's timed events
      tomorrowTimed.append(event)
    }
  }

  // Split today's timed events into past (already ended) and active (ongoing/upcoming)
  let pastTimed = todayTimed.filter { $0.endDate <= now }
  let activeTimed = todayTimed.filter { $0.endDate > now }

  // Find next upcoming event (timed, not all-day, not already ended)
  let upcomingTimed = activeTimed + tomorrowTimed
  let nextEvent = upcomingTimed.first

  // Build variables
  let todayCount = todayAllDay.count + todayTimed.count
  let tomorrowCount = tomorrowAllDay.count + tomorrowTimed.count
  let nextTitle = nextEvent?.title ?? ""
  let nextCountdown =
    nextEvent.map { event in
      if event.startDate <= now {
        return "now"
      }
      return formatCountdown(from: now, to: event.startDate)
    } ?? ""
  let nextTime = nextEvent.map { formatTime($0.startDate) } ?? ""

  var variables: [String: String] = [
    "next_title": nextTitle,
    "next_countdown": nextCountdown,
    "next_time": nextTime,
    "today_count": "\(todayCount)",
    "tomorrow_count": "\(tomorrowCount)",
    "has_allday": todayAllDay.isEmpty ? "" : "true",
    "has_tomorrow": tomorrowCount > 0 ? "true" : "",
    "has_past": pastTimed.isEmpty ? "" : "true",
  ]

  if let next = nextEvent {
    variables["next_color"] = next.calendarColor
    variables["next_calendar"] = next.calendarName
  }

  // Determine bar visibility based on upcoming window
  let hasEvents: Bool
  if let upcomingWindow = settings.upcomingInterval {
    // Only show bar when next event starts within the upcoming window, or is happening now
    let windowEnd = now.addingTimeInterval(upcomingWindow)
    hasEvents =
      nextEvent.map { event in
        event.startDate <= windowEnd
      } ?? false
  } else {
    // No upcoming window set — show whenever there are events today
    hasEvents = nextEvent != nil || !todayAllDay.isEmpty
  }

  // Build data collections
  var dataCollections: [String: [[String: String]]] = [:]

  dataCollections["past_events"] = pastTimed.map { event in
    [
      "title": event.title,
      "time": formatTimeRange(event.startDate, event.endDate),
      "color": event.calendarColor,
      "calendar": event.calendarName,
    ]
  }

  dataCollections["today_events"] = activeTimed.map { event in
    var dict: [String: String] = [
      "title": event.title,
      "time": formatTimeRange(event.startDate, event.endDate),
      "color": event.calendarColor,
      "calendar": event.calendarName,
    ]
    if event.startDate <= now {
      dict["countdown"] = "now"
    } else {
      dict["countdown"] = formatCountdown(from: now, to: event.startDate)
    }
    return dict
  }

  dataCollections["tomorrow_events"] = tomorrowTimed.map { event in
    [
      "title": event.title,
      "time": formatTimeRange(event.startDate, event.endDate),
      "color": event.calendarColor,
      "calendar": event.calendarName,
    ]
  }

  dataCollections["allday_events"] = todayAllDay.map { event in
    [
      "title": event.title,
      "color": event.calendarColor,
      "calendar": event.calendarName,
    ]
  }

  // Build view tree
  var viewChildren: [JSONValue] = []

  // Today header
  viewChildren.append(header("Today"))

  // All-day events as badges
  viewChildren.append(
    conditional(
      variable: "has_allday",
      then: foreach(
        items: "allday_events",
        child: badge(content: "{title}", color: "{color}", textColor: "#FFFFFF"))))

  // Past events (strikethrough + muted)
  viewChildren.append(
    conditional(
      variable: "has_past",
      then: foreach(
        items: "past_events",
        child: hstack(
          spacing: 8, padding: .array([.double(4), .double(0), .double(4), .double(0)]),
          children: [
            rect(width: 3, height: 24, color: "{color}", cornerRadius: 1.5),
            vstack(
              spacing: 1,
              children: [
                textNode("{title}", size: 13, style: "secondary", strikethrough: true),
                textNode("{time}", size: 11, style: "secondary", strikethrough: true),
              ]),
            spacer(),
          ]))))

  // Active (ongoing/upcoming) timed events
  if activeTimed.isEmpty && pastTimed.isEmpty {
    viewChildren.append(text("No events today", size: 12, style: "secondary"))
  } else if !activeTimed.isEmpty {
    viewChildren.append(
      foreach(
        items: "today_events",
        child: hstack(
          spacing: 8, padding: .array([.double(4), .double(0), .double(4), .double(0)]),
          children: [
            rect(width: 3, height: 24, color: "{color}", cornerRadius: 1.5),
            vstack(
              spacing: 1,
              children: [
                text("{title}", size: 13, weight: "medium"),
                text("{time}", size: 11, style: "secondary"),
              ]),
            spacer(),
            text("{countdown}", size: 11, style: "secondary"),
          ])))
  }

  // Tomorrow section (conditional)
  viewChildren.append(
    conditional(
      variable: "has_tomorrow",
      then: group(children: [
        divider(),
        header("Tomorrow"),
        foreach(
          items: "tomorrow_events",
          child: hstack(
            spacing: 8, padding: .array([.double(4), .double(0), .double(4), .double(0)]),
            children: [
              rect(width: 3, height: 24, color: "{color}", cornerRadius: 1.5),
              vstack(
                spacing: 1,
                children: [
                  text("{title}", size: 13, weight: "medium"),
                  text("{time}", size: 11, style: "secondary"),
                ]),
              spacer(),
            ])),
      ])))

  // Open Calendar action
  viewChildren.append(divider())
  viewChildren.append(
    action(label: "Calendar", icon: settings.icons.action, command: "open -a Calendar"))

  let view = vstack(
    spacing: 8,
    padding: .array([.double(12), .double(16), .double(12), .double(16)]),
    frame: .object(["w": .int(320)]),
    children: viewChildren
  )

  // Format display value
  let value = applyFormat(settings.format, variables: variables)

  let output = PluginOutput(
    value: value,
    icon: settings.icons.icon,
    hidden: !hasEvents,
    variables: variables,
    data: dataCollections,
    view: view
  )

  printJSON(output)
  return 0
}

// MARK: - Main

func main() -> Int32 {
  let args = CommandLine.arguments

  if args.count >= 2, args[1] == "--watch" {
    return watchMode()
  }

  return defaultMode()
}

exit(main())
