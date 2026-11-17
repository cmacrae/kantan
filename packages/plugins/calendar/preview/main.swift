import Foundation

// Prints the states of the calendar module's preview: the events of Monday
// 16 November 2026, seen before a meeting and during it.

/// A state of the preview: its name and the output the plugin prints in it.
struct PreviewState: Encodable {
  let name: String
  let output: PluginOutput
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
    calendarColor: calendar == "Work" ? "#1E66F5" : "#40A02B", calendarName: calendar)
}

let events = [
  event("Standup", at(9), at(9, 15)),
  event("Design review", at(11), at(12)),
  event("Climbing", at(18, 30), at(20), calendar: "Personal"),
  event("Planning", at(10, days: 1), at(11, days: 1)),
]
let settings = loadSettings(defaults: Settings())

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let preview = [
  "states": [
    PreviewState(
      name: "Upcoming", output: render(events: events, settings: settings, now: at(10, 35))),
    PreviewState(
      name: "Underway", output: render(events: events, settings: settings, now: at(11, 10))),
  ]
]
print(String(decoding: try encoder.encode(preview), as: UTF8.self))
