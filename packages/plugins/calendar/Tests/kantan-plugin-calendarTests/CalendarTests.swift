import Foundation
import Testing

@testable import kantan_plugin_calendar

final class CalendarRenderTests {
  private let today = Calendar.current.startOfDay(for: Date())

  /// Today, or `days` later, at `hour:minute`.
  private func at(_ hour: Int, _ minute: Int = 0, days: Int = 0) -> Date {
    let day = Calendar.current.date(byAdding: .day, value: days, to: today)!
    return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
  }

  private func event(_ title: String, _ start: Date, _ end: Date, allDay: Bool = false)
    -> CalendarEvent
  {
    CalendarEvent(
      title: title, startDate: start, endDate: end, isAllDay: allDay, calendarColor: "#FF0000",
      calendarName: "Work")
  }

  private lazy var day = [
    event("Standup", at(8), at(8, 30)),
    event("Review", at(10, 30), at(11)),
    event("Planning", at(9, days: 1), at(10, days: 1)),
  ]

  @Test func testCountsDownToTheNextEvent() {
    let output = render(events: day, settings: Settings(), now: at(9))
    #expect(output.value == "Review in 1h 30m")
    #expect(output.variables["upcoming"] == "true")
    #expect(output.variables["active"] == "")
    #expect(output.variables["today_count"] == "2")
    #expect(output.variables["tomorrow_count"] == "1")
    #expect((output.data["past_events"]?.map { $0["title"] }) == ["Standup"])
    #expect((output.data["today_events"]?.map { $0["countdown"] }) == ["1h 30m"])
    #expect(output.hidden == false)
  }

  @Test func testAnEventUnderwayIsNow() {
    let output = render(events: day, settings: Settings(), now: at(10, 45))
    #expect(output.value == "Review now")
    #expect(output.variables["active"] == "true")
  }

  @Test func testAnEventAboutToStartTakesOverFromALongOneUnderway() {
    let events = [event("Focus", at(9), at(17)), event("Sync", at(14), at(14, 30))]
    #expect(render(events: events, settings: Settings(), now: at(13, 55)).value == "Sync in 5m")
    #expect(render(events: events, settings: Settings(), now: at(14, 10)).value == "Sync now")
    #expect(render(events: events, settings: Settings(), now: at(14, 40)).value == "Focus now")
  }

  @Test func testAnUpcomingWindowHidesEventsBeyondIt() {
    var settings = Settings()
    settings.upcoming = "30m"
    #expect(render(events: day, settings: settings, now: at(9)).hidden == true)
    #expect(render(events: day, settings: settings, now: at(10, 15)).hidden == false)
  }

  @Test func testEventsTakeTheColourTheirCalendarIsGiven() throws {
    let colors = try JSONDecoder().decode(
      ColorConfig.self,
      from: Data(##"{"event":"#111111","calendars":{"Home":"inherit","Work":"#222222"}}"##.utf8))
    #expect(colors.color(ofCalendar: "Work", own: "#FF0000") == "#222222")
    #expect(colors.color(ofCalendar: "Home", own: "#00FF00") == "#00FF00")
    #expect(colors.color(ofCalendar: "Other", own: "#0000FF") == "#111111")
    #expect(ColorConfig().color(ofCalendar: "Work", own: "#FF0000") == "#FF0000")

    var settings = Settings()
    settings.colors = colors
    let output = render(events: day, settings: settings, now: at(9))
    #expect(output.variables["next_color"] == "#222222")
    #expect((output.data["today_events"]?.map { $0["color"] }) == ["#222222"])
  }

  @Test func testAnEventOfCalendarsOpensInCalendar() {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let event = CalendarEvent(
      title: "Sync", startDate: start, endDate: start.addingTimeInterval(3600), isAllDay: false,
      calendarColor: "#FF0000", calendarName: "Work", id: "A1:B2/C3")
    #expect(
      event.openCommand
        == "open 'ical://ekevent/20270115T080000Z/A1:B2%2FC3?method=show&options=more'")
    #expect(day[0].openCommand == nil)
  }

  @Test func testCountdowns() {
    let now = at(9)
    #expect(formatCountdown(from: now, to: now.addingTimeInterval(30)) == "<1m")
    #expect(formatCountdown(from: now, to: at(9, 45)) == "45m")
    #expect(formatCountdown(from: now, to: at(11)) == "2h")
    #expect(formatCountdown(from: now, to: at(8)) == "now")
  }
}

final class FullCalendarTests {
  /// November 2026 on `day` at `hour`.
  private func at(day: Int, hour: Int = 0) -> Date {
    Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
  }

  private func event(_ title: String, day: Int, from start: Int, to end: Int) -> CalendarEvent {
    CalendarEvent(
      title: title, startDate: at(day: day, hour: start), endDate: at(day: day, hour: end),
      isAllDay: false, calendarColor: "#FF0000", calendarName: "Work")
  }

  @Test func testTheMonthPicksADayAndListsItsEvents() throws {
    var settings = Settings()
    settings.mode = .full
    let events = [
      event("Standup", day: 18, from: 9, to: 10), event("Review", day: 18, from: 14, to: 15),
      event("Offsite", day: 20, from: 10, to: 16),
    ]
    let now = at(day: 18, hour: 12)

    let today = render(events: events, settings: settings, now: now, module: "cal")
    #expect((today.data["agenda_past"]?.map { $0["title"] }) == ["Standup"])
    #expect((today.data["agenda_events"]?.map { $0["countdown"] }) == ["2h"])
    // The bar still counts down to today's next event.
    #expect(today.value == "Review in 2h")
    let view = String(decoding: try JSONEncoder().encode(today.view), as: UTF8.self)
    for day in 1...30 {
      let key = String(format: "2026-11-%02d", day)
      #expect(
        view.contains("kantan-plugin-calendar --select \(key) && kantan trigger 'cal' refresh"))
    }

    let picked = try #require(ViewState().applying("--select", "2026-11-20", at: now))
    let offsite = render(events: events, settings: settings, now: now, state: picked, module: "cal")
    #expect((offsite.data["agenda_events"]?.map { $0["title"] }) == ["Offsite"])
    #expect(offsite.data["agenda_events"]?.first?["countdown"] == nil)
  }

  @Test func testTheViewFollowsItsButtonsForTheDay() throws {
    let now = at(day: 18, hour: 12)
    let picked = try #require(ViewState().applying("--select", "2026-11-20", at: now))
    #expect(picked.selectedDay(at: now) == at(day: 20))
    #expect(picked.shownMonth(at: now) == at(day: 1))

    let next = try #require(picked.applying("--month", "2", at: now))
    #expect(next.shownMonth(at: now) == Calendar.current.date(from: DateComponents(year: 2027))!)
    #expect(next.selectedDay(at: now) == at(day: 20))
    #expect(next.applying("--today", nil, at: now) == ViewState())

    // The next day, the calendar opens on today again.
    #expect(next.selectedDay(at: at(day: 19)) == at(day: 19))
    #expect(next.shownMonth(at: at(day: 19)) == at(day: 1))

    #expect(picked.applying("--select", "tomorrow", at: now) == nil)
    #expect(picked.applying("--sideways", nil, at: now) == nil)
  }
}

// MARK: - PluginKit formats

final class FormatTests {
  private func format(_ json: String) throws -> Format {
    try JSONDecoder().decode(Format.self, from: Data(json.utf8))
  }

  @Test func testAStringIsATemplate() throws {
    let format = try format(#""{name}{?late: late}""#)
    #expect(format == .template("{name}{?late: late}"))
    #expect(format.apply(["name": "Sync", "late": "true"]).value == "Sync late")
    #expect(format.apply([:]).segments == nil)
  }

  @Test func testSegmentsShowWhileTheirVariableIsTruthyOrWithBangFalsy() throws {
    let format = try format(
      #"""
      [{"text": "{name}", "fg": "#FFFFFF"}, {"text": " late", "when": "late"},
       {"text": " on time", "when": "!late"}, {"text": "{?!name:?}"}]
      """#)
    #expect(
      format.apply(["name": "Sync", "late": "true"]).segments == [
        ValueSegment(text: "Sync", fg: "#FFFFFF"), ValueSegment(text: " late", fg: nil),
      ])
    let onTime = format.apply(["name": "Sync"])
    #expect(onTime.value == "Sync on time")
    #expect(onTime.segments?.map(\.text) == ["Sync", " on time"])
  }
}

// MARK: - PluginKit watch mode

@MainActor
final class WatchTests {
  @Test func testOutputSkipsRepeatsOfTheLastLine() {
    var lines: [String] = []
    let output = WatchOutput { lines.append(String(decoding: $0, as: UTF8.self)) }
    output.show(PluginOutput(value: "a"))
    output.show(PluginOutput(value: "a"))
    output.show(PluginOutput(value: "b"))
    output.show(PluginOutput(value: "a"))
    #expect(
      lines == (["a", "b", "a"].map { #"{"data":{},"value":"\#($0)","variables":{}}"# + "\n" }))
  }
}
