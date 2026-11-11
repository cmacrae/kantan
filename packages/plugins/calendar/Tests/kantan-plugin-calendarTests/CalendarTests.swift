import XCTest

@testable import kantan_plugin_calendar

final class CalendarRenderTests: XCTestCase {
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

  func testCountsDownToTheNextEvent() {
    let output = render(events: day, settings: Settings(), now: at(9))
    XCTAssertEqual(output.value, "Review in 1h 30m")
    XCTAssertEqual(output.variables["upcoming"], "true")
    XCTAssertEqual(output.variables["active"], "")
    XCTAssertEqual(output.variables["today_count"], "2")
    XCTAssertEqual(output.variables["tomorrow_count"], "1")
    XCTAssertEqual(output.data["past_events"]?.map { $0["title"] }, ["Standup"])
    XCTAssertEqual(output.data["today_events"]?.map { $0["countdown"] }, ["1h 30m"])
    XCTAssertEqual(output.hidden, false)
  }

  func testAnEventUnderwayIsNow() {
    let output = render(events: day, settings: Settings(), now: at(10, 45))
    XCTAssertEqual(output.value, "Review now")
    XCTAssertEqual(output.variables["active"], "true")
  }

  func testAnUpcomingWindowHidesEventsBeyondIt() {
    var settings = Settings()
    settings.upcoming = "30m"
    XCTAssertEqual(render(events: day, settings: settings, now: at(9)).hidden, true)
    XCTAssertEqual(render(events: day, settings: settings, now: at(10, 15)).hidden, false)
  }

  func testCountdowns() {
    let now = at(9)
    XCTAssertEqual(formatCountdown(from: now, to: now.addingTimeInterval(30)), "<1m")
    XCTAssertEqual(formatCountdown(from: now, to: at(9, 45)), "45m")
    XCTAssertEqual(formatCountdown(from: now, to: at(11)), "2h")
    XCTAssertEqual(formatCountdown(from: now, to: at(8)), "now")
  }
}

// MARK: - PluginKit formats

final class FormatTests: XCTestCase {
  private func format(_ json: String) throws -> Format {
    try JSONDecoder().decode(Format.self, from: Data(json.utf8))
  }

  func testAStringIsATemplate() throws {
    let format = try format(#""{name}{?late: late}""#)
    XCTAssertEqual(format, .template("{name}{?late: late}"))
    XCTAssertEqual(format.apply(["name": "Sync", "late": "true"]).value, "Sync late")
    XCTAssertNil(format.apply([:]).segments)
  }

  func testSegmentsShowWhileTheirVariableIsTruthyOrWithBangFalsy() throws {
    let format = try format(
      #"""
      [{"text": "{name}", "fg": "#FFFFFF"}, {"text": " late", "when": "late"},
       {"text": " on time", "when": "!late"}, {"text": "{?!name:?}"}]
      """#)
    XCTAssertEqual(
      format.apply(["name": "Sync", "late": "true"]).segments,
      [ValueSegment(text: "Sync", fg: "#FFFFFF"), ValueSegment(text: " late", fg: nil)])
    let onTime = format.apply(["name": "Sync"])
    XCTAssertEqual(onTime.value, "Sync on time")
    XCTAssertEqual(onTime.segments?.map(\.text), ["Sync", " on time"])
  }
}

// MARK: - PluginKit watch mode

@MainActor
final class WatchTests: XCTestCase {
  func testOutputSkipsRepeatsOfTheLastLine() {
    var lines: [String] = []
    let output = WatchOutput { lines.append(String(decoding: $0, as: UTF8.self)) }
    output.show(PluginOutput(value: "a"))
    output.show(PluginOutput(value: "a"))
    output.show(PluginOutput(value: "b"))
    output.show(PluginOutput(value: "a"))
    XCTAssertEqual(
      lines,
      ["a", "b", "a"].map { #"{"data":{},"value":"\#($0)","variables":{}}"# + "\n" })
  }
}
