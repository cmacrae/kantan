import Foundation
import Testing

@testable import kantan_plugin_reminders

private func decode<T: Decodable>(_ json: String) throws -> T {
  try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

final class ReminderFilterTests {
  private let now = Date()

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

  @Test func testHiddenWithoutIncompleteReminders() throws {
    let settings: Settings = try decode(#"{"lists":[{"name":"todo"}]}"#)
    let output = render(incomplete: [], completed: [], settings: settings, module: "todo", now: now)
    #expect(output.hidden == true)
    #expect(output.value == "")
  }
}
