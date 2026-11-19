import Foundation

// Prints the states of the calendar module's preview: the events of Monday
// 16 November 2026, seen before a meeting and during it. The full calendar
// is also seen with each of the two months either side shown, so its
// buttons for the months and for today lead from one state to another.

/// A state of the preview: its name, the output the plugin prints in it,
/// and the output each command run from it leads to.
struct PreviewState: Encodable {
  let name: String
  let output: PluginOutput
  var after: [String: PluginOutput] = [:]
}

/// 16 November 2026 at `hour:minute`, `days` days on.
func at(_ hour: Int, _ minute: Int = 0, days: Int = 0) -> Date {
  Calendar.current.date(
    from: DateComponents(year: 2026, month: 11, day: 16 + days, hour: hour, minute: minute))!
}

func event(_ title: String, _ start: Date, _ end: Date, calendar: String = "Work")
  -> CalendarEvent
{
  CalendarEvent(
    title: title, startDate: start, endDate: end, isAllDay: false,
    calendarColor: calendar == "Work" ? "#1E66F5" : "#40A02B", calendarName: calendar,
    id: title)
}

let events = [
  CalendarEvent(
    title: "Release day", startDate: at(0), endDate: at(23, 59), isAllDay: true,
    calendarColor: "#1E66F5", calendarName: "Work", id: "Release day"),
  event("Standup", at(9), at(9, 15)),
  event("Event", at(11), at(12)),
  event("Climbing", at(18, 30), at(20), calendar: "Personal"),
  event("Planning", at(10, days: 1), at(11, days: 1)),
  // Events in the months either side, for the full calendar to show.
  event("Review", at(14, days: -61), at(15, days: -61)),
  event("Workshop", at(10, days: -40), at(16, days: -40)),
  event("Retro", at(15, days: -19), at(16, days: -19)),
  event("Dinner", at(19, days: -12), at(21, days: -12), calendar: "Personal"),
  event("Offsite", at(9, days: 17), at(17, days: 17)),
  event("Concert", at(20, days: 26), at(23, days: 26), calendar: "Personal"),
  event("Kickoff", at(10, days: 56), at(11, days: 56)),
]
let settings: Settings = {
  var settings = loadSettings(defaults: Settings())
  // Colours that are names of settings come with what they fall back to.
  settings.colors.givesFallbacks =
    ProcessInfo.processInfo.environment["KANTAN_SETTINGS"]?.contains("{setting(") ?? false
  // Each calendar's colour is then the name of its setting, set or not.
  if settings.colors.givesFallbacks {
    for calendar in Set(events.map(\.calendarName))
    where settings.colors.calendars[calendar] == nil {
      settings.colors.calendars[calendar] = "{setting(colors.calendars.\(calendar))}"
    }
  }
  return settings
}()

let module = moduleName(fallback: "calendar")

/// How many months either side of this one the full calendar is seen at.
let monthsEitherSide = 2

/// The state named `name` at `now`, with the full calendar as `view` has it.
/// Its buttons for the months and for today lead where they lead from there.
func state(_ name: String, now: Date, view: ViewState = ViewState()) -> PreviewState {
  let output = { (view: ViewState) in
    render(events: events, settings: settings, now: now, state: view, module: module)
  }
  var after: [String: PluginOutput] = [:]
  if settings.mode == .full {
    for (command, argument) in [("--month", "-1"), ("--month", "1"), ("--today", nil)] {
      if let next = view.applying(command, argument, at: now) {
        after[viewCommand(command, argument, module: module)] = output(next)
      }
    }
  }
  return PreviewState(name: name, output: output(view), after: after)
}

/// The states seen at `now`: the one named `name`, and for the full
/// calendar one for each other month it is seen at, named for the month.
func states(_ name: String, now: Date) -> [PreviewState] {
  guard settings.mode == .full else { return [state(name, now: now)] }
  let month = DateFormatter()
  month.dateFormat = "LLLL"
  let others = (-monthsEitherSide...monthsEitherSide).filter { $0 != 0 }.compactMap {
    offset -> PreviewState? in
    guard let view = ViewState().applying("--month", "\(offset)", at: now) else { return nil }
    return state("\(name), \(month.string(from: view.shownMonth(at: now)))", now: now, view: view)
  }
  return [state(name, now: now)] + others
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let preview = ["states": states("Upcoming", now: at(10, 35)) + states("Underway", now: at(11, 10))]
print(String(decoding: try encoder.encode(preview), as: UTF8.self))
