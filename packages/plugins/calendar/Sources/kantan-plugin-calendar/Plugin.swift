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
  /// The buttons of the full calendar that show the month before and after.
  var previous: String
  var next: String

  static let defaults = IconConfig(
    icon: "calendar-event-filled",
    action: "calendar-event-filled",
    previous: "chevron-left",
    next: "chevron-right"
  )

  private enum CodingKeys: String, CodingKey {
    case icon, action, previous, next
  }

  init(icon: String, action: String, previous: String, next: String) {
    self.icon = icon
    self.action = action
    self.previous = previous
    self.next = next
  }

  init(from decoder: Decoder) throws {
    let d = Self.defaults
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.icon = container.setting(String.self, forKey: .icon) ?? d.icon
    self.action = container.setting(String.self, forKey: .action) ?? d.action
    self.previous = container.setting(String.self, forKey: .previous) ?? d.previous
    self.next = container.setting(String.self, forKey: .next) ?? d.next
  }
}

/// What a click on the module opens: `compact` lists today's and tomorrow's
/// events, and `full` shows a month to pick a day from, over that day's.
enum Mode: String, Decodable {
  case compact, full
}

/// The colours of the module's views. All but `event` and `calendars` are
/// the full calendar's.
struct ColorConfig: Decodable {
  /// What stands for the colour a calendar has in the Calendar app.
  static let inherit = "inherit"

  /// The colour of each calendar's events, by the calendar's name, and of
  /// the events of a calendar it doesn't name: a colour, or `inherit`.
  var calendars: [String: String] = [:]
  var event = ColorConfig.inherit
  /// Whether a colour is given with the one it falls back to after it, as
  /// `colour|fallback`. A preview's generator sets it, as its colours may be
  /// names of settings left unset.
  var givesFallbacks = false
  /// The circle behind today, and today's number on it.
  var today = "accent"
  var todayText = "white"
  /// The circle behind the day picked.
  var selected = "#8E8E934D"
  /// The badge on an event under way, and its text, or nil for the system's.
  var now: String?
  var nowText: String?
  /// The buttons that change the month and go back to today, and the one
  /// that opens Calendar, or nil for the system's.
  var navigation: String?
  var action: String?
  /// The dot under a day with events, or nil for the colour of the day's
  /// first event's calendar.
  var dot: String?

  private enum CodingKeys: String, CodingKey {
    case event, calendars, today, selected, now, navigation, action, dot
    case todayText = "today_text"
    case nowText = "now_text"
  }

  init() {}

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.event = container.setting(String.self, forKey: .event) ?? event
    self.calendars = container.setting([String: String].self, forKey: .calendars) ?? calendars
    self.today = container.setting(String.self, forKey: .today) ?? today
    self.todayText = container.setting(String.self, forKey: .todayText) ?? todayText
    self.selected = container.setting(String.self, forKey: .selected) ?? selected
    self.now = container.setting(String.self, forKey: .now)
    self.nowText = container.setting(String.self, forKey: .nowText)
    self.navigation = container.setting(String.self, forKey: .navigation)
    self.action = container.setting(String.self, forKey: .action)
    self.dot = container.setting(String.self, forKey: .dot)
  }

  /// The colour of an event of the calendar named `calendar`, whose colour
  /// in the Calendar app is `own`.
  func color(ofCalendar calendar: String, own: String) -> String {
    let unnamed = falling(event, to: own)
    guard let given = calendars[calendar] else { return unnamed }
    return given == Self.inherit ? own : falling(given, to: unnamed)
  }

  /// The colour of the dot under a day whose first event has `color`.
  func dotColor(over color: String) -> String {
    dot.map { falling($0, to: color) } ?? color
  }

  private func falling(_ color: String, to fallback: String) -> String {
    if color == Self.inherit { return fallback }
    return givesFallbacks ? "\(color)|\(fallback)" : color
  }
}

struct Settings: Decodable {
  var format: Format
  var upcoming: String?
  var calendars: CalendarFilter?
  var icons: IconConfig
  var mode: Mode
  var colors: ColorConfig

  private enum CodingKeys: String, CodingKey {
    case format, upcoming, calendars, icons, mode, colors
  }

  init() {
    self.format = .template("{next_title}{?upcoming: in} {next_countdown}")
    self.upcoming = nil
    self.calendars = nil
    self.icons = .defaults
    self.mode = .compact
    self.colors = ColorConfig()
  }

  init(from decoder: Decoder) throws {
    let defaults = Settings()
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.format = container.setting(Format.self, forKey: .format) ?? defaults.format
    self.upcoming = container.setting(String.self, forKey: .upcoming)
    self.icons = container.setting(IconConfig.self, forKey: .icons) ?? defaults.icons
    self.mode = container.setting(Mode.self, forKey: .mode) ?? defaults.mode
    self.colors = container.setting(ColorConfig.self, forKey: .colors) ?? defaults.colors

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
  var calendarColor: String
  let calendarName: String
  /// What Calendar knows the event by, when it is one of Calendar's.
  var id: String? = nil

  /// The command that shows the event in Calendar, or nil without an `id`.
  /// The address names the occurrence by when it starts: in UTC, or for an
  /// event that lasts all day, on the day as it is here.
  var openCommand: String? {
    guard let id else { return nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = isAllDay ? .current : TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    let occurrence = formatter.string(from: startDate)
    let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
    let name = id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id
    return "open "
      + shellQuote("ical://ekevent/\(occurrence)/\(name)?method=show&options=more")
  }

  /// What a view lists of the event, with `time` as when it is.
  func fields(time: String?) -> [String: String] {
    var fields = ["title": title, "color": calendarColor, "calendar": calendarName]
    fields["time"] = time
    fields["open_cmd"] = openCommand
    return fields
  }
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

/// Whether an event with `status`, which the user answered with
/// `participation` (nil when they aren't invited), belongs on the bar: not
/// cancelled or declined.
func isAttended(status: EKEventStatus, participation: EKParticipantStatus?) -> Bool {
  status != .canceled && participation != .declined
}

/// The events of `calendars` in any of `spans`, each once. EventKit reads
/// at most four years at a time, so each span is read on its own.
func fetchEvents(store: EKEventStore, calendars: [EKCalendar], in spans: [DateInterval])
  -> [CalendarEvent]
{
  var seen = Set<String>()
  let events = spans.flatMap { span in
    store.events(
      matching: store.predicateForEvents(
        withStart: span.start, end: span.end, calendars: calendars))
  }.filter { event in
    seen.insert("\(event.calendarItemIdentifier)\n\(event.startDate.timeIntervalSince1970)")
      .inserted
      && isAttended(
        status: event.status,
        participation: event.attendees?.first(where: \.isCurrentUser)?.participantStatus)
  }

  return events.map { event in
    CalendarEvent(
      title: event.title ?? "Untitled",
      startDate: event.startDate,
      endDate: event.endDate,
      isAllDay: event.isAllDay,
      calendarColor: hexColor(from: event.calendar.cgColor),
      calendarName: event.calendar.title,
      id: event.calendarItemIdentifier
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

// MARK: - Days

/// `date`'s day as `yyyy-MM-dd` in `calendar`.
func dayKey(_ date: Date, in calendar: Calendar = .current) -> String {
  let parts = calendar.dateComponents([.year, .month, .day], from: date)
  return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
}

/// The start of the day `key` names as `yyyy-MM-dd` in `calendar`, or of
/// its month for `yyyy-MM`. A month is any `calendar` has, such as the
/// Hebrew calendar's 13th.
func parseDay(_ key: String, in calendar: Calendar = .current) -> Date? {
  let parts = key.split(separator: "-").map { Int($0) }
  guard (2...3).contains(parts.count), let year = parts[0], let month = parts[1],
    calendar.maximumRange(of: .month)?.contains(month) == true,
    let day = parts.count == 3 ? parts[2] : 1, (1...31).contains(day)
  else { return nil }
  return calendar.date(from: DateComponents(year: year, month: month, day: day))
}

/// The start of `date`'s month.
func startOfMonth(_ date: Date) -> Date {
  Calendar.current.dateInterval(of: .month, for: date)?.start ?? date
}

/// The events of `events` that fall on the day starting at `dayStart`.
func events(on dayStart: Date, of events: [CalendarEvent]) -> [CalendarEvent] {
  let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
  return events.filter { $0.startDate < dayEnd && $0.endDate > dayStart }
}

// MARK: - View State

/// What the full calendar shows, as its buttons left it.
struct ViewState: Codable, Equatable {
  /// The day whose events are listed, as `yyyy-MM-dd`, or nil for today.
  var selected: String?
  /// The month shown, as `yyyy-MM`, or nil for the selected day's.
  var month: String?
  /// The day the buttons were last used, as `yyyy-MM-dd`. The state lasts
  /// that day, so the calendar opens on today the next.
  var setOn: String?

  /// The day picked at `now`, as the start of it.
  func selectedDay(at now: Date) -> Date {
    let today = Calendar.current.startOfDay(for: now)
    guard setOn == dayKey(now) else { return today }
    return selected.flatMap { parseDay($0) } ?? today
  }

  /// The month shown at `now`, as the start of it.
  func shownMonth(at now: Date) -> Date {
    let fromDay = startOfMonth(selectedDay(at: now))
    guard setOn == dayKey(now) else { return fromDay }
    return month.flatMap { parseDay($0) } ?? fromDay
  }

  /// The state after the subcommand `command` is run with `argument` at
  /// `now`, or nil when they aren't a subcommand that changes it.
  func applying(_ command: String, _ argument: String?, at now: Date) -> ViewState? {
    switch command {
    case "--select":
      guard let argument, argument.count == 10, parseDay(argument) != nil else { return nil }
      return ViewState(selected: argument, month: nil, setOn: dayKey(now))
    case "--month":
      guard let months = argument.flatMap({ Int($0) }),
        let month = Calendar.current.date(byAdding: .month, value: months, to: shownMonth(at: now))
      else { return nil }
      return ViewState(
        selected: dayKey(selectedDay(at: now)), month: String(dayKey(month).prefix(7)),
        setOn: dayKey(now))
    case "--today":
      return ViewState()
    default:
      return nil
    }
  }
}

/// The file the view state is kept in.
func viewStateURL() -> URL {
  let environment = ProcessInfo.processInfo.environment
  let cache =
    environment["XDG_CACHE_HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache")
  return cache.appendingPathComponent("kantan").appendingPathComponent("calendar.json")
}

func loadViewState() -> ViewState {
  guard let data = try? Data(contentsOf: viewStateURL()) else { return ViewState() }
  return (try? JSONDecoder().decode(ViewState.self, from: data)) ?? ViewState()
}

func saveViewState(_ state: ViewState) throws {
  let url = viewStateURL()
  try FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  try JSONEncoder().encode(state).write(to: url, options: .atomic)
}

/// The command that runs the subcommand `command` with `argument`, then
/// refreshes the module named `module`.
func viewCommand(_ command: String, _ argument: String? = nil, module: String) -> String {
  "kantan-plugin-calendar \(command)" + (argument.map { " \($0)" } ?? "")
    + " && kantan trigger \(shellQuote(module)) refresh"
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
  let module = moduleName(fallback: "calendar")
  Watch { currentOutput(store: store, settings: settings, module: module) }
    .run(on: .EKEventStoreChanged, from: store)
}

// MARK: - Output

/// The output while kantan has no access to calendars.
let noAccessOutput = PluginOutput(value: "", hidden: true, view: vstack(children: []))

/// The module's output for the events in `store` at `now`, for the module
/// named `module`.
func currentOutput(
  store: EKEventStore, settings: Settings, module: String, now: Date = Date()
) -> PluginOutput {
  let calendars = filteredCalendars(store: store, settings: settings)
  guard !calendars.isEmpty else {
    return PluginOutput(
      value: "No calendars", hidden: true,
      view: vstack(children: [text("No calendars found", style: "secondary")]))
  }
  let calendar = Calendar.current
  let todayStart = calendar.startOfDay(for: now)
  var spans = [
    DateInterval(start: todayStart, end: calendar.date(byAdding: .day, value: 2, to: todayStart)!)
  ]
  // The full calendar also shows the month's events, and the picked day's.
  let state = settings.mode == .full ? loadViewState() : ViewState()
  if settings.mode == .full {
    let month = state.shownMonth(at: now)
    let selected = state.selectedDay(at: now)
    spans += [
      DateInterval(start: month, end: calendar.date(byAdding: .month, value: 1, to: month)!),
      DateInterval(start: selected, end: calendar.date(byAdding: .day, value: 1, to: selected)!),
    ]
  }
  return render(
    events: fetchEvents(store: store, calendars: calendars, in: spans),
    settings: settings, now: now, state: state, module: module)
}

/// The module's output for `events`, in the order `fetchEvents` returns
/// them, at `now`: today's and tomorrow's, and for the full calendar, which
/// shows what `state` says and refreshes the module named `module`, those
/// of the month shown and the day picked.
func render(
  events: [CalendarEvent], settings: Settings, now: Date, state: ViewState = ViewState(),
  module: String = "calendar"
) -> PluginOutput {
  let todayStart = Calendar.current.startOfDay(for: now)
  let tomorrowStart = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)!
  let tomorrowEnd = Calendar.current.date(byAdding: .day, value: 2, to: todayStart)!
  // Each event in the colour the settings give its calendar.
  let events = events.map { event in
    var event = event
    event.calendarColor = settings.colors.color(
      ofCalendar: event.calendarName, own: event.calendarColor)
    return event
  }
  let allEvents = events.filter { $0.startDate < tomorrowEnd && $0.endDate > todayStart }

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

  // The next event: of the timed ones not yet ended, the one starting
  // nearest now, so a long event underway gives way to one about to start
  let upcomingTimed = activeTimed + tomorrowTimed
  let nextEvent = upcomingTimed.min { a, b in
    abs(a.startDate.timeIntervalSince(now)) < abs(b.startDate.timeIntervalSince(now))
  }

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

  dataCollections["past_events"] = pastTimed.map {
    $0.fields(time: formatTimeRange($0.startDate, $0.endDate))
  }

  dataCollections["today_events"] = activeTimed.map { event in
    var dict = event.fields(time: formatTimeRange(event.startDate, event.endDate))
    if event.startDate <= now {
      dict["countdown"] = "now"
    } else {
      dict["countdown"] = formatCountdown(from: now, to: event.startDate)
    }
    return dict
  }

  // All-day events first, as has_tomorrow counts them too
  dataCollections["tomorrow_events"] = (tomorrowAllDay + tomorrowTimed).map {
    $0.fields(time: $0.isAllDay ? "All day" : formatTimeRange($0.startDate, $0.endDate))
  }

  dataCollections["allday_events"] = todayAllDay.map { $0.fields(time: "All day") }

  if settings.mode == .full {
    let full = fullView(events: events, settings: settings, now: now, state: state, module: module)
    dataCollections.merge(full.data) { _, agenda in agenda }
    let (value, segments) = settings.format.apply(variables)
    return PluginOutput(
      value: value, segments: segments, icon: settings.icons.icon, hidden: !hasEvents,
      variables: variables, data: dataCollections, view: full.view)
  }

  // Build view tree
  var viewChildren: [JSONValue] = []

  // Today header
  viewChildren.append(header("Today"))

  // All-day events, drawn as the timed ones still to come are
  viewChildren.append(
    conditional(
      variable: "has_allday",
      then: foreach(
        items: "allday_events",
        child: hstack(
          spacing: 8,
          padding: .object([
            "top": .double(4), "leading": .double(0), "bottom": .double(4), "trailing": .double(0),
          ]),
          command: "{open_cmd}",
          children: [
            rect(width: 3, height: 24, color: "{color}", cornerRadius: 1.5),
            vstack(
              spacing: 1,
              children: [
                text("{title}", size: 13, weight: "medium"),
                text("{time}", size: 11, style: "secondary"),
              ]),
            spacer(),
          ]))))

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
          command: "{open_cmd}",
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
    if todayAllDay.isEmpty {
      viewChildren.append(text("No events today", size: 12, style: "secondary"))
    }
  } else if !activeTimed.isEmpty {
    viewChildren.append(
      foreach(
        items: "today_events",
        child: hstack(
          spacing: 8,
          padding: .object([
            "top": .double(4), "leading": .double(0), "bottom": .double(4), "trailing": .double(0),
          ]),
          command: "{open_cmd}",
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
            command: "{open_cmd}",
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

// MARK: - Full Calendar

/// The sizes of a day's cell in the month, in points: the cell, the circle
/// that marks its number, and the dot under it.
private let cellSize = 24.0
private let markSize = 22.0
private let dotSize = 4.0

/// The padding around an event's row.
private let rowPadding: JSONValue = .object([
  "top": .double(1), "leading": .double(0), "bottom": .double(1), "trailing": .double(0),
])

/// The full calendar's view at `now`: the month `state` shows, each day a
/// button that picks it, over the events of the day picked, which are the
/// `data` the view lists.
func fullView(
  events allEvents: [CalendarEvent], settings: Settings, now: Date, state: ViewState,
  module: String
) -> (view: JSONValue, data: [String: [[String: String]]]) {
  let calendar = Calendar.current
  let today = calendar.startOfDay(for: now)
  let selected = state.selectedDay(at: now)
  let month = state.shownMonth(at: now)
  let colors = settings.colors

  // The month's name and year, and the buttons that change it.
  let title = DateFormatter()
  title.dateFormat = "LLLL yyyy"
  let navigation = hstack(
    spacing: 10,
    children: [
      text(title.string(from: month), size: 13, weight: "semibold"),
      spacer(),
      button(
        icon: settings.icons.previous, command: viewCommand("--month", "-1", module: module),
        color: colors.navigation, dismiss: false),
      button(
        label: "Today", command: viewCommand("--today", module: module),
        color: colors.navigation, dismiss: false),
      button(
        icon: settings.icons.next, command: viewCommand("--month", "1", module: module),
        color: colors.navigation, dismiss: false),
    ])

  // A column for each day of the week, from the day the week starts on.
  let symbols = calendar.veryShortStandaloneWeekdaySymbols
  var cells = (0..<7).map {
    text(
      symbols[(calendar.firstWeekday - 1 + $0) % 7], size: 10, style: "secondary",
      align: "center")
  }
  // Blanks up to the weekday the month starts on.
  let blank = rect(width: cellSize, height: cellSize + dotSize)
  let leading = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
  cells += Array(repeating: blank, count: leading)
  for number in calendar.range(of: .day, in: .month, for: month) ?? 1..<1 {
    guard let date = calendar.date(byAdding: .day, value: number - 1, to: month) else { continue }
    let select = viewCommand("--select", dayKey(date), module: module)
    var layers: [JSONValue] = []
    if date == today {
      layers = [
        circle(size: markSize, color: colors.today),
        button(
          label: "\(number)", command: select, style: "plain", color: colors.todayText,
          dismiss: false),
      ]
    } else {
      if date == selected {
        layers.append(circle(size: markSize, color: colors.selected))
      }
      layers.append(button(label: "\(number)", command: select, style: "plain", dismiss: false))
    }
    // A dot in the colour the settings give, or the day's first event's.
    let dot = events(on: date, of: allEvents).first.map {
      circle(size: dotSize, color: colors.dotColor(over: $0.calendarColor))
    }
    cells.append(
      vstack(
        spacing: 0, alignment: "center",
        children: [
          zstack(children: layers).framed(w: cellSize, h: cellSize),
          dot ?? circle(size: dotSize),
        ]))
  }

  // Blanks after the month's last day, up to the six weeks the longest
  // month spans, so every month is as tall as any other.
  cells += Array(repeating: blank, count: max(0, 7 * 7 - cells.count))

  // The events of the day picked: those that last all day, then those
  // over, then those under way or still to come.
  let dayEvents = events(on: selected, of: allEvents)
  let allDay = dayEvents.filter(\.isAllDay)
  let timed = dayEvents.filter { !$0.isAllDay }
  let isToday = selected == today
  let past = isToday ? timed.filter { $0.endDate <= now } : []
  let rest = isToday ? timed.filter { $0.endDate > now } : timed
  let row = { (event: CalendarEvent) in
    event.fields(time: formatTimeRange(event.startDate, event.endDate))
  }
  let data: [String: [[String: String]]] = [
    "agenda_allday": allDay.map { $0.fields(time: "All day") },
    "agenda_past": past.map(row),
    "agenda_events": rest.map { event in
      var fields = row(event)
      if isToday {
        let underway = event.startDate <= now
        fields["now"] = underway ? "true" : ""
        fields["countdown"] = underway ? "" : formatCountdown(from: now, to: event.startDate)
      }
      return fields
    },
  ]

  let heading: String
  if isToday {
    heading = "Today"
  } else if selected == calendar.date(byAdding: .day, value: 1, to: today) {
    heading = "Tomorrow"
  } else {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEEE d MMMM"
    heading = formatter.string(from: selected)
  }

  let eventRow = { (title: JSONValue, time: JSONValue, trailing: [JSONValue]) in
    hstack(
      spacing: 8, padding: rowPadding, command: "{open_cmd}",
      children: [
        rect(width: 3, height: 24, color: "{color}", cornerRadius: 1.5),
        vstack(spacing: 0, children: [title, time]),
        spacer(),
      ] + trailing)
  }
  var agenda: [JSONValue] = []
  if !allDay.isEmpty {
    agenda.append(
      foreach(
        items: "agenda_allday",
        child: eventRow(
          text("{title}", size: 13, weight: "medium"),
          text("{time}", size: 11, style: "secondary"), [])))
  }
  if !past.isEmpty {
    agenda.append(
      foreach(
        items: "agenda_past",
        child: eventRow(
          text("{title}", size: 13, style: "secondary", strikethrough: true),
          text("{time}", size: 11, style: "secondary", strikethrough: true), [])))
  }
  if !rest.isEmpty {
    agenda.append(
      foreach(
        items: "agenda_events",
        child: eventRow(
          text("{title}", size: 13, weight: "medium"),
          text("{time}", size: 11, style: "secondary"),
          [
            badge(content: "now", color: colors.now, textColor: colors.nowText).visible(
              when: "now"),
            text("in {countdown}", size: 11, style: "secondary").visible(when: "countdown"),
          ])))
  }

  var children: [JSONValue] = [
    navigation,
    grid(columns: 7, spacing: 2, children: cells),
    divider(),
    header(heading),
  ]
  if agenda.isEmpty {
    children.append(text("No events", size: 12, style: "secondary"))
  } else if dayEvents.count > 4 {
    // A long day scrolls, so the popup stays a height the screen has.
    children.append(scroll(children: [vstack(spacing: 0, children: agenda)]).framed(maxH: 150))
  } else {
    // In a stack of their own, the rows sit closer than the sections do.
    children.append(vstack(spacing: 0, children: agenda))
  }
  children.append(divider())
  // A button, which sits closer to what is around it than an action does.
  children.append(
    hstack(children: [
      button(
        label: "Calendar", icon: settings.icons.action, command: "open -a Calendar",
        color: colors.action),
      spacer(),
    ]))

  let view = vstack(
    spacing: 6, padding: .double(12), frame: .object(["w": .int(252)]), children: children)
  return (view, data)
}

// MARK: - Main

@MainActor
func main() -> Int32 {
  let arguments = Array(CommandLine.arguments.dropFirst())
  if arguments.first == "--watch" {
    watchMode()
  }
  if let command = arguments.first {
    guard
      let state = loadViewState().applying(
        command, arguments.count > 1 ? arguments[1] : nil, at: Date())
    else {
      fputs("unknown command: \(arguments.joined(separator: " "))\n", stderr)
      return 1
    }
    do {
      try saveViewState(state)
      return 0
    } catch {
      fputs("Failed to save the calendar's view: \(error)\n", stderr)
      return 1
    }
  }
  let settings = loadSettings(defaults: Settings())
  let store = EKEventStore()
  let module = moduleName(fallback: "calendar")
  printJSON(
    ensureAccess(store: store)
      ? currentOutput(store: store, settings: settings, module: module) : noAccessOutput)
  return 0
}
