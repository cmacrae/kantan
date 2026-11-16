import EventKit
import Foundation

// MARK: - Settings

/// Per-list configuration decoded from KANTAN_SETTINGS.
struct ListConfig: Decodable {
  var name: String
  var icon: String
  var lookahead: String
  var overdue: Bool
  var undated: Bool
  var completedRetention: String
  var maxChars: Int

  private enum CodingKeys: String, CodingKey {
    case name, icon, lookahead, overdue, undated, completedRetention, maxChars
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.name = try container.decode(String.self, forKey: .name)
    self.icon = container.setting(String.self, forKey: .icon) ?? ""
    self.lookahead = container.setting(String.self, forKey: .lookahead) ?? "10m"
    self.overdue = container.setting(Bool.self, forKey: .overdue) ?? true
    self.undated = container.setting(Bool.self, forKey: .undated) ?? false
    self.completedRetention =
      container.setting(String.self, forKey: .completedRetention) ?? "0"
    self.maxChars = container.setting(Int.self, forKey: .maxChars) ?? 30
  }

  var lookaheadInterval: TimeInterval {
    parseDuration(lookahead) ?? 600
  }

  var retentionInterval: TimeInterval {
    parseDuration(completedRetention) ?? 0
  }
}

/// Icon configuration for the reminders plugin.
/// Values are icon names resolved by kantan's bundled icon font system
/// (e.g. "list-check"). Raw Unicode glyphs are also accepted.
struct IconConfig: Decodable {
  var action: String

  static let defaults = IconConfig(action: "list-check")

  private enum CodingKeys: String, CodingKey {
    case action
  }

  init(action: String) {
    self.action = action
  }

  init(from decoder: Decoder) throws {
    let d = Self.defaults
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.action = container.setting(String.self, forKey: .action) ?? d.action
  }
}

struct Settings: Decodable {
  var lists: [ListConfig]
  var format: String
  var icons: IconConfig

  private enum CodingKeys: String, CodingKey {
    case lists, format, icons
  }

  init() {
    self.lists = []
    self.format = "{title}"
    self.icons = .defaults
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.lists = container.setting([ListConfig].self, forKey: .lists) ?? []
    self.format = container.setting(String.self, forKey: .format) ?? "{title}"
    self.icons = container.setting(IconConfig.self, forKey: .icons) ?? .defaults
  }
}

// MARK: - Helpers

func truncate(_ string: String, maxChars: Int) -> String {
  guard maxChars > 0, string.count > maxChars else { return string }
  return String(string.prefix(maxChars)) + "..."
}

// MARK: - EventKit Operations

/// Request full access to reminders, blocking until the user responds.
/// Returns true if access was granted.
func ensureAccess(store: EKEventStore) -> Bool {
  switch EKEventStore.authorizationStatus(for: .reminder) {
  case .fullAccess, .authorized:
    return true
  case .notDetermined:
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var granted = false
    store.requestFullAccessToReminders { result, error in
      if let error {
        fputs("Error requesting reminders access: \(error)\n", stderr)
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

/// A reminder, as the module shows it.
struct Reminder {
  let id: String
  let title: String
  /// The name of the list it's in.
  let list: String
  let dueDate: Date?
  let completionDate: Date?
}

extension Reminder {
  init(_ reminder: EKReminder) {
    self.init(
      id: reminder.calendarItemIdentifier, title: reminder.title ?? "Untitled",
      list: reminder.calendar.title, dueDate: reminder.dueDateComponents?.date,
      completionDate: reminder.completionDate)
  }
}

/// Whether an incomplete reminder due at `dueDate` shows from `list` at
/// `now`: overdue and undated ones as the list says, the rest once they
/// fall within its lookahead.
func isShown(dueDate: Date?, from list: ListConfig, now: Date) -> Bool {
  guard let dueDate else { return list.undated }
  if dueDate < now { return list.overdue }
  return dueDate <= now.addingTimeInterval(list.lookaheadInterval)
}

/// Whether a reminder completed at `completionDate` still shows from `list`
/// at `now`, within the list's retention.
func isRetained(completionDate: Date?, from list: ListConfig, now: Date) -> Bool {
  guard list.retentionInterval > 0, let completionDate else { return false }
  return completionDate >= now.addingTimeInterval(-list.retentionInterval)
}

/// The shown incomplete reminders of `lists`, soonest due first with
/// undated ones last, and their retained completed ones, latest first.
func fetchReminders(store: EKEventStore, lists: [ListConfig], now: Date)
  -> (incomplete: [Reminder], completed: [Reminder])
{
  let configs = Dictionary(lists.map { ($0.name, $0) }) { first, _ in first }
  let calendars = store.calendars(for: .reminder).filter { configs[$0.title] != nil }
  guard !calendars.isEmpty else { return ([], []) }

  let incomplete = fetch(
    store,
    store.predicateForIncompleteReminders(
      withDueDateStarting: nil, ending: nil, calendars: calendars)
  ).filter { reminder in
    configs[reminder.list].map { isShown(dueDate: reminder.dueDate, from: $0, now: now) } ?? false
  }.sorted { a, b in
    switch (a.dueDate, b.dueDate) {
    case (let da?, let db?): return da < db
    case (_?, nil): return true
    default: return false
    }
  }

  let retention = lists.map(\.retentionInterval).max() ?? 0
  guard retention > 0 else { return (incomplete, []) }
  let completed = fetch(
    store,
    store.predicateForCompletedReminders(
      withCompletionDateStarting: now.addingTimeInterval(-retention), ending: now,
      calendars: calendars)
  ).filter { reminder in
    configs[reminder.list].map {
      isRetained(completionDate: reminder.completionDate, from: $0, now: now)
    } ?? false
  }.sorted { ($0.completionDate ?? .distantPast) > ($1.completionDate ?? .distantPast) }
  return (incomplete, completed)
}

/// The reminders `predicate` matches, waiting for EventKit to fetch them.
func fetch(_ store: EKEventStore, _ predicate: NSPredicate) -> [Reminder] {
  let semaphore = DispatchSemaphore(value: 0)
  nonisolated(unsafe) var result: [Reminder] = []
  store.fetchReminders(matching: predicate) { reminders in
    result = (reminders ?? []).map(Reminder.init)
    semaphore.signal()
  }
  semaphore.wait()
  return result
}

// MARK: - Subcommands

/// Complete a reminder by its calendarItemIdentifier.
func completeReminder(id: String) -> Int32 {
  let store = EKEventStore()
  guard ensureAccess(store: store) else {
    fputs("No access to reminders\n", stderr)
    return 1
  }

  guard let item = store.calendarItem(withIdentifier: id) as? EKReminder else {
    fputs("Reminder not found: \(id)\n", stderr)
    return 1
  }

  item.isCompleted = true
  item.completionDate = Date()
  do {
    try store.save(item, commit: true)
    return 0
  } catch {
    fputs("Failed to complete reminder: \(error)\n", stderr)
    return 1
  }
}

/// Uncomplete a reminder by its calendarItemIdentifier.
func uncompleteReminder(id: String) -> Int32 {
  let store = EKEventStore()
  guard ensureAccess(store: store) else {
    fputs("No access to reminders\n", stderr)
    return 1
  }

  guard let item = store.calendarItem(withIdentifier: id) as? EKReminder else {
    fputs("Reminder not found: \(id)\n", stderr)
    return 1
  }

  item.isCompleted = false
  item.completionDate = nil
  do {
    try store.save(item, commit: true)
    return 0
  } catch {
    fputs("Failed to uncomplete reminder: \(error)\n", stderr)
    return 1
  }
}

// MARK: - Watch Mode

/// Prints the module's output whenever it may have changed: once a burst of
/// reminder changes settles, and at the start of every minute, as
/// reminders come due. One event store serves every update.
@MainActor
func watchMode() -> Never {
  let settings = loadSettings(defaults: Settings())
  guard !settings.lists.isEmpty else {
    fputs("No lists configured in settings\n", stderr)
    idleWatch(showing: hiddenOutput)
  }
  let store = EKEventStore()
  guard ensureAccess(store: store) else {
    fputs("No access to reminders\n", stderr)
    idleWatch(showing: hiddenOutput)
  }
  let module = moduleName(fallback: "reminders")
  Watch { currentOutput(store: store, settings: settings, module: module) }
    .run(on: .EKEventStoreChanged, from: store)
}

// MARK: - Output

/// The output while there are no lists to show or no access to them.
let hiddenOutput = PluginOutput(value: "", hidden: true, view: vstack(children: []))

/// The module's output for the reminders in `store` at `now`, for the
/// module named `module`.
func currentOutput(store: EKEventStore, settings: Settings, module: String, now: Date = Date())
  -> PluginOutput
{
  let reminders = fetchReminders(store: store, lists: settings.lists, now: now)
  return render(
    incomplete: reminders.incomplete, completed: reminders.completed, settings: settings,
    module: module, now: now)
}

/// The module's output for its shown `incomplete` and `completed`
/// reminders at `now`, whose menu refreshes the module named `module`.
func render(
  incomplete: [Reminder], completed: [Reminder], settings: Settings, module modName: String,
  now: Date
) -> PluginOutput {
  let hasReminders = !incomplete.isEmpty

  // Determine displayed reminder (first incomplete)
  let displayedReminder = incomplete.first
  let displayedListConfig =
    displayedReminder.flatMap { r in settings.lists.first { $0.name == r.list } }
    ?? settings.lists.first

  let maxChars = displayedListConfig?.maxChars ?? 30
  let title = displayedReminder?.title ?? ""
  let iconName = displayedListConfig?.icon
  let listName = displayedReminder?.list ?? displayedListConfig?.name ?? ""

  // Format due date if available
  let due: String = {
    guard let date = displayedReminder?.dueDate else { return "" }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: now)
  }()

  // Build data collections and view tree
  let allItems = incomplete + completed
  let hasMultiple = allItems.count > 1

  var dataCollections: [String: [[String: String]]] = [:]
  var viewChildren: [JSONValue] = []

  if hasMultiple {
    // Group reminders by list name
    let incompleteByList = Dictionary(grouping: incomplete, by: \.list)
    let completedByList = Dictionary(grouping: completed, by: \.list)

    // Determine which lists have items, preserving config order
    let listsWithItems = settings.lists.filter { lc in
      !(incompleteByList[lc.name] ?? []).isEmpty || !(completedByList[lc.name] ?? []).isEmpty
    }
    let showHeaders = settings.lists.count > 1
    for (index, lc) in listsWithItems.enumerated() {
      let listIncomplete = incompleteByList[lc.name] ?? []
      let listCompleted = completedByList[lc.name] ?? []

      if showHeaders {
        if index > 0 { viewChildren.append(divider()) }
        viewChildren.append(header(lc.name))
      }

      // Build per-list data collection keys
      let safeKey = lc.name.replacingOccurrences(of: " ", with: "_")
      let incKey = "incomplete_\(safeKey)"
      let compKey = "completed_\(safeKey)"

      let item = { (reminder: Reminder) in
        [
          "title": truncate(reminder.title, maxChars: lc.maxChars),
          "complete_cmd": completionCommand("--complete", reminder, module: modName),
          "uncomplete_cmd": completionCommand("--uncomplete", reminder, module: modName),
        ]
      }
      dataCollections[incKey] = listIncomplete.map(item)
      dataCollections[compKey] = listCompleted.map(item)

      if !listIncomplete.isEmpty {
        viewChildren.append(
          foreach(
            items: incKey,
            child: check(
              label: "{title}", checked: false, command: "{complete_cmd}",
              uncheckedCommand: "{uncomplete_cmd}")))
      }
      if !listCompleted.isEmpty {
        viewChildren.append(
          foreach(
            items: compKey,
            child: check(
              label: "{title}", checked: true, command: "{complete_cmd}",
              uncheckedCommand: "{uncomplete_cmd}")))
      }
    }
  } else if hasReminders {
    // Single incomplete reminder — show a "Complete" action
    if let reminder = displayedReminder {
      viewChildren.append(
        action(
          label: "Complete", command: completionCommand("--complete", reminder, module: modName)))
    }
  } else {
    // No reminders at all
    viewChildren.append(text("No reminders", style: "secondary"))
  }

  viewChildren.append(divider())
  viewChildren.append(
    action(label: "Reminders", icon: settings.icons.action, command: "open x-apple-reminderkit://"))

  let view = vstack(
    spacing: 8,
    padding: .object([
      "top": .double(12), "leading": .double(16), "bottom": .double(12), "trailing": .double(16),
    ]),
    frame: .object(["w": .int(280)]),
    children: viewChildren
  )

  // Template variables
  var variables: [String: String] = [
    "count": "\(incomplete.count)",
    "total": "\(incomplete.count + completed.count)",
    "title": truncate(title, maxChars: maxChars),
    "full_title": title,
    "list": listName,
    "due": due,
  ]

  // Add icon as a variable too
  if let iconName, !iconName.isEmpty {
    variables["list_icon"] = iconName
  }

  // Apply format string to produce the displayed value
  let value = applyFormat(settings.format, variables: variables)

  return PluginOutput(
    value: value,
    icon: iconName,
    hidden: !hasReminders,
    variables: variables,
    data: dataCollections,
    view: view
  )
}

/// The command that runs `subcommand` (`--complete` or `--uncomplete`) on
/// `reminder`, then refreshes the module named `module`.
func completionCommand(_ subcommand: String, _ reminder: Reminder, module: String) -> String {
  "kantan-plugin-reminders \(subcommand) \(shellQuote(reminder.id))"
    + " && kantan trigger \(shellQuote(module)) refresh"
}

// MARK: - Main

@MainActor
func main() -> Int32 {
  let args = CommandLine.arguments

  if args.count >= 3, args[1] == "--complete" {
    return completeReminder(id: args[2])
  }

  if args.count >= 3, args[1] == "--uncomplete" {
    return uncompleteReminder(id: args[2])
  }

  if args.count >= 2, args[1] == "--watch" {
    watchMode()
  }

  let settings = loadSettings(defaults: Settings())
  guard !settings.lists.isEmpty else {
    fputs("No lists configured in settings\n", stderr)
    printJSON(hiddenOutput)
    return 0
  }
  let store = EKEventStore()
  let module = moduleName(fallback: "reminders")
  printJSON(
    ensureAccess(store: store)
      ? currentOutput(store: store, settings: settings, module: module) : hiddenOutput)
  return 0
}

exit(main())
