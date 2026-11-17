import Foundation

// Prints the states of the reminders module's preview: two reminders, with
// each combination of them ticked off, so ticking one in a state's menu
// leads to another state.

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
]

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

/// The state named `name`, with `completed` ticked off: ticking another
/// reminder off, or one back on, leads to the state with that set.
func state(_ name: String, completed: Set<String>) -> PreviewState {
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
  return PreviewState(name: name, output: output(completed: completed), after: after)
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let preview = [
  "states": [
    state("Due", completed: []),
    state("Dentist done", completed: ["1"]),
    state("Garage done", completed: ["2"]),
    state("All done", completed: ["1", "2"]),
  ]
]
print(String(decoding: try encoder.encode(preview), as: UTF8.self))
