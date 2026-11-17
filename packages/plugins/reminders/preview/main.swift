import Foundation

// Prints the states of the reminders module's preview: three reminders,
// with each combination of them ticked off, so ticking one in a state's
// menu leads to another state.

/// A state of the preview: its name, the output the plugin prints in it,
/// and the output each command run from it leads to.
struct PreviewState: Encodable {
  let name: String
  let output: PluginOutput
  let after: [String: PluginOutput]
}

/// Monday 16 November 2026 at `hour:minute`.
func at(_ hour: Int, _ minute: Int = 0) -> Date {
  Calendar.current.date(
    from: DateComponents(year: 2026, month: 11, day: 16, hour: hour, minute: minute))!
}

let now = at(14, 55)
let module = moduleName(fallback: "reminders")
let settings = loadSettings(defaults: Settings())
let reminders = [
  Reminder(
    id: "1", title: "Book the dentist", list: "Reminders", dueDate: at(14, 30),
    completionDate: nil),
  Reminder(
    id: "2", title: "Call the garage", list: "Reminders", dueDate: at(15), completionDate: nil),
  Reminder(
    id: "3", title: "Run 5k", list: "Reminders", dueDate: at(15, 5), completionDate: nil),
]

/// What each reminder is called in a state's name.
let shortNames = ["1": "Dentist", "2": "Garage", "3": "Run"]

/// The output with the reminders `completed` ticked off just now.
func output(completed: Set<String>) -> PluginOutput {
  render(
    incomplete: reminders.filter { !completed.contains($0.id) },
    completed: reminders.filter { completed.contains($0.id) }.map {
      Reminder(
        id: $0.id, title: $0.title, list: $0.list, dueDate: $0.dueDate, completionDate: now)
    },
    settings: settings, module: module, now: now)
}

/// The name of the state with `completed` ticked off: `Due`, `All done`,
/// or the reminders done, as in `Dentist and run done`.
func name(completed: Set<String>) -> String {
  if completed.isEmpty { return "Due" }
  if completed.count == reminders.count { return "All done" }
  let done = reminders.filter { completed.contains($0.id) }.compactMap { shortNames[$0.id] }
  let listed = done.dropFirst().reduce(done[0]) { "\($0) and \($1.lowercased())" }
  return "\(listed) done"
}

/// The state with `completed` ticked off: ticking another reminder off, or
/// one back on, leads to the state with that set.
func state(completed: Set<String>) -> PreviewState {
  var after: [String: PluginOutput] = [:]
  for reminder in reminders {
    if completed.contains(reminder.id) {
      after[completionCommand("--uncomplete", reminder, module: module)] = output(
        completed: completed.subtracting([reminder.id]))
    } else {
      after[completionCommand("--complete", reminder, module: module)] = output(
        completed: completed.union([reminder.id]))
    }
  }
  return PreviewState(
    name: name(completed: completed), output: output(completed: completed), after: after)
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
/// Every set of the reminders, the smallest first.
let subsets = reminders.reduce([Set<String>()]) { sets, reminder in
  sets + sets.map { $0.union([reminder.id]) }
}.sorted { ($0.count, $0.sorted().joined()) < ($1.count, $1.sorted().joined()) }
let preview = ["states": subsets.map(state)]
print(String(decoding: try encoder.encode(preview), as: UTF8.self))
