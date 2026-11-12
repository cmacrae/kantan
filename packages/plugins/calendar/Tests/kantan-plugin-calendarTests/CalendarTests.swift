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

  @Test func testAnUpcomingWindowHidesEventsBeyondIt() {
    var settings = Settings()
    settings.upcoming = "30m"
    #expect(render(events: day, settings: settings, now: at(9)).hidden == true)
    #expect(render(events: day, settings: settings, now: at(10, 15)).hidden == false)
  }

  @Test func testCountdowns() {
    let now = at(9)
    #expect(formatCountdown(from: now, to: now.addingTimeInterval(30)) == "<1m")
    #expect(formatCountdown(from: now, to: at(9, 45)) == "45m")
    #expect(formatCountdown(from: now, to: at(11)) == "2h")
    #expect(formatCountdown(from: now, to: at(8)) == "now")
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
