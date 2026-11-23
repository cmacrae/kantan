import Foundation
import Testing

@testable import kantan_plugin_reminders

private func decode<T: Decodable>(_ json: String) throws -> T {
  try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

final class ReminderFilterTests {
  private let now = Date()

  @Test func testShellQuoteEscapesAQuoteWithACombiningMarkAfterIt() {
    #expect(shellQuote("a'\u{301}; id") == #"'a'\''"# + "\u{301}; id'")
  }

  @Test func testAListEntryWithoutANameIsLeftOutAndTheOthersKept() throws {
    let settings: Settings = try decode(
      #"{"lists":[{"name":"todo"},{"icon":"home"},{"name":7},"work",{"name":"work"}]}"#)
    #expect(settings.lists.map(\.name) == ["todo", "work"])
    let none: Settings = try decode(#"{"lists":"todo"}"#)
    #expect(none.lists.isEmpty)
  }

  @Test func testIncompleteRemindersShowAsTheListSays() throws {
    let list: ListConfig = try decode(
      #"{"name":"todo","lookahead":"10m","overdue":false,"undated":true}"#)
    #expect(isShown(dueDate: nil, from: list, now: now))
    #expect(!isShown(dueDate: now.addingTimeInterval(-60), from: list, now: now))
    #expect(isShown(dueDate: now.addingTimeInterval(9 * 60), from: list, now: now))
    #expect(!isShown(dueDate: now.addingTimeInterval(11 * 60), from: list, now: now))

    let defaults: ListConfig = try decode(#"{"name":"todo"}"#)
    #expect(!isShown(dueDate: nil, from: defaults, now: now))
    #expect(isShown(dueDate: now.addingTimeInterval(-60), from: defaults, now: now))
  }

  @Test func testCompletedRemindersShowWithinTheListsRetention() throws {
    let list: ListConfig = try decode(#"{"name":"todo","completedRetention":"1h"}"#)
    #expect(isRetained(completionDate: now.addingTimeInterval(-1800), from: list, now: now))
    #expect(!isRetained(completionDate: now.addingTimeInterval(-7200), from: list, now: now))
    #expect(!isRetained(completionDate: nil, from: list, now: now))
    let none: ListConfig = try decode(#"{"name":"todo"}"#)
    #expect(!isRetained(completionDate: now, from: none, now: now))
  }
}

final class ReminderRenderTests {
  private let now = Date()

  private func reminder(
    _ id: String, _ title: String, list: String = "todo", completed: Bool = false
  )
    -> Reminder
  {
    Reminder(
      id: id, title: title, list: list, dueDate: nil, completionDate: completed ? now : nil)
  }

  @Test func testShowsTheFirstIncompleteReminder() throws {
    let settings: Settings = try decode(
      #"{"lists":[{"name":"todo","icon":"bell","maxChars":5}],"format":"{title} ({count})"}"#)
    let output = render(
      incomplete: [reminder("1", "Buy milk"), reminder("2", "Call")],
      completed: [reminder("3", "Post", completed: true)], settings: settings, module: "chores",
      now: now)
    #expect(output.value == "Buy m... (2)")
    #expect(output.icon == "bell")
    #expect(output.hidden == false)
    #expect(output.variables["full_title"] == "Buy milk")
    #expect(output.variables["total"] == "3")
    #expect((output.data["incomplete_todo"]?.map { $0["title"] }) == ["Buy m...", "Call"])
    #expect((output.data["completed_todo"]?.map { $0["title"] }) == ["Post"])
    #expect(
      output.data["incomplete_todo"]?.first?["complete_cmd"]
        == "kantan-plugin-reminders --complete '1' && kantan trigger 'chores' refresh")
  }

  @Test func testWithoutPersistTheModuleHidesOnceNoneAreIncomplete() throws {
    let settings: Settings = try decode(
      #"{"lists":[{"name":"todo","completedRetention":"1h"}],"persist":false}"#)
    let post = reminder("1", "Post", completed: true)
    let done = render(
      incomplete: [], completed: [post], settings: settings, module: "todo", now: now)
    #expect(done.hidden == true)
    let left = render(
      incomplete: [reminder("2", "Call")], completed: [post], settings: settings, module: "todo",
      now: now)
    #expect(left.hidden == false)
    #expect((left.data["completed_todo"]?.map { $0["title"] }) == ["Post"])
  }

  @Test func testTodaysProgressOpensTheMenu() throws {
    let settings: Settings = try decode(
      ##"{"lists":[{"name":"todo"}],"progress":true,"progressColor":"#FF0000"}"##)
    let output = render(
      incomplete: [reminder("1", "Call")], completed: [],
      today: TodayProgress(done: 3, total: 8), settings: settings, module: "todo", now: now)
    #expect(output.variables["today_done"] == "3")
    #expect(output.variables["today_total"] == "8")
    let view = String(decoding: try JSONEncoder().encode(output.view), as: UTF8.self)
    #expect(view.contains(#""value":0.375"#))
    #expect(view.contains(##""color":"#FF0000""##))

    let without = render(
      incomplete: [reminder("1", "Call")], completed: [], settings: settings, module: "todo",
      now: now)
    #expect(
      !String(decoding: try JSONEncoder().encode(without.view), as: UTF8.self).contains("progress"))
  }

  @Test func testHiddenWithoutIncompleteReminders() throws {
    let settings: Settings = try decode(#"{"lists":[{"name":"todo"}]}"#)
    let output = render(incomplete: [], completed: [], settings: settings, module: "todo", now: now)
    #expect(output.hidden == true)
    #expect(output.value == "")
  }
}
