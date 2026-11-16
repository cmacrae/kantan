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
    self.icon = container.setting(String.self, forKey: .icon) ?? d.icon
    self.action = container.setting(String.self, forKey: .action) ?? d.action
  }
}

struct Settings: Decodable {
  var format: Format
  var upcoming: String?
  var calendars: CalendarFilter?
  var icons: IconConfig

  private enum CodingKeys: String, CodingKey {
    case format, upcoming, calendars, icons
  }

  init() {
    self.format = .template("{next_title}{?upcoming: in} {next_countdown}")
    self.upcoming = nil
    self.calendars = nil
    self.icons = .defaults
  }

  init(from decoder: Decoder) throws {
    let defaults = Settings()
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.format = container.setting(Format.self, forKey: .format) ?? defaults.format
    self.upcoming = container.setting(String.self, forKey: .upcoming)
    self.icons = container.setting(IconConfig.self, forKey: .icons) ?? defaults.icons

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

// MARK: - Watch Mode

/// Prints the module's output whenever it may have changed: once a burst of
/// calendar changes settles, and at the start of every minute, as
/// countdowns count down. One event store serves every update.
@MainActor
func watchMode() -> Never {
  let settings = loadSettings(defaults: Settings())
  let store = EKEventStore()
  guard ensureAccess(store: store) else {
    fputs("No access to calendar events\n", stderr)
    idleWatch(showing: noAccessOutput)
  }
  Watch { currentOutput(store: store, settings: settings) }
    .run(on: .EKEventStoreChanged, from: store)
}

// MARK: - Output

/// The output while kantan has no access to calendars.
let noAccessOutput = PluginOutput(value: "", hidden: true, view: vstack(children: []))

/// The module's output for the events in `store` at `now`.
func currentOutput(store: EKEventStore, settings: Settings, now: Date = Date()) -> PluginOutput {
  let calendars = filteredCalendars(store: store, settings: settings)
  guard !calendars.isEmpty else {
    return PluginOutput(
      value: "No calendars", hidden: true,
      view: vstack(children: [text("No calendars found", style: "secondary")]))
  }
  let todayStart = Calendar.current.startOfDay(for: now)
  let tomorrowEnd = Calendar.current.date(byAdding: .day, value: 2, to: todayStart)!
  return render(
    events: fetchEvents(store: store, calendars: calendars, from: todayStart, to: tomorrowEnd),
    settings: settings, now: now)
}

/// The module's output for `events`, today's and tomorrow's in the order
/// `fetchEvents` returns them, at `now`.
func render(events allEvents: [CalendarEvent], settings: Settings, now: Date) -> PluginOutput {
  let todayStart = Calendar.current.startOfDay(for: now)
  let tomorrowStart = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)!

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
  let nextIsActive = nextEvent.map { $0.startDate <= now } ?? false
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
    "active": nextIsActive ? "true" : "",
    "upcoming": nextIsActive ? "" : (nextEvent != nil ? "true" : ""),
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
          spacing: 8,
          padding: .object([
            "top": .double(4), "leading": .double(0), "bottom": .double(4), "trailing": .double(0),
          ]),
          children: [
            rect(width: 3, height: 24, color: "{color}", cornerRadius: 1.5),
            vstack(
              spacing: 1,
              children: [
                text("{title}", size: 13, style: "secondary", strikethrough: true),
                text("{time}", size: 11, style: "secondary", strikethrough: true),
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
          spacing: 8,
          padding: .object([
            "top": .double(4), "leading": .double(0), "bottom": .double(4), "trailing": .double(0),
          ]),
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
            spacing: 8,
            padding: .object([
              "top": .double(4), "leading": .double(0), "bottom": .double(4),
              "trailing": .double(0),
            ]),
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
    padding: .object([
      "top": .double(12), "leading": .double(16), "bottom": .double(12), "trailing": .double(16),
    ]),
    frame: .object(["w": .int(320)]),
    children: viewChildren
  )

  // Format display value
  let (value, segments) = settings.format.apply(variables)

  return PluginOutput(
    value: value,
    segments: segments,
    icon: settings.icons.icon,
    hidden: !hasEvents,
    variables: variables,
    data: dataCollections,
    view: view
  )
}

// MARK: - Main

@MainActor
func main() -> Int32 {
  if CommandLine.arguments.dropFirst().first == "--watch" {
    watchMode()
  }
  let settings = loadSettings(defaults: Settings())
  let store = EKEventStore()
  printJSON(
    ensureAccess(store: store) ? currentOutput(store: store, settings: settings) : noAccessOutput)
  return 0
}

exit(main())
