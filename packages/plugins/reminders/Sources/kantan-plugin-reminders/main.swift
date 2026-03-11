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
    self.icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? ""
    self.lookahead = try container.decodeIfPresent(String.self, forKey: .lookahead) ?? "10m"
    self.overdue = try container.decodeIfPresent(Bool.self, forKey: .overdue) ?? true
    self.undated = try container.decodeIfPresent(Bool.self, forKey: .undated) ?? false
    self.completedRetention =
      try container.decodeIfPresent(String.self, forKey: .completedRetention) ?? "0"
    self.maxChars = try container.decodeIfPresent(Int.self, forKey: .maxChars) ?? 30
  }

  var lookaheadInterval: TimeInterval {
    parseDuration(lookahead) ?? 600
  }

  var retentionInterval: TimeInterval {
    parseDuration(completedRetention) ?? 0
  }
}

struct Settings: Decodable {
  var lists: [ListConfig]
  var format: String

  private enum CodingKeys: String, CodingKey {
    case lists, format
  }

  init() {
    self.lists = []
    self.format = "{title}"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.lists = try container.decodeIfPresent([ListConfig].self, forKey: .lists) ?? []
    self.format = try container.decodeIfPresent(String.self, forKey: .format) ?? "{title}"
  }
}

/// Read the module name from KANTAN_MODULE_NAME env var (set by kantan).
func moduleName() -> String {
  ProcessInfo.processInfo.environment["KANTAN_MODULE_NAME"] ?? "reminders"
}

func loadSettings() -> Settings {
  guard let json = ProcessInfo.processInfo.environment["KANTAN_SETTINGS"],
    let data = json.data(using: .utf8)
  else {
    return Settings()
  }
  return (try? JSONDecoder().decode(Settings.self, from: data)) ?? Settings()
}

// MARK: - Duration Parsing

/// Parses a duration string like "10m", "12h", "2d" into seconds.
func parseDuration(_ string: String) -> TimeInterval? {
  let trimmed = string.trimmingCharacters(in: .whitespaces).lowercased()
  guard trimmed.count >= 2 else { return nil }

  let suffix = trimmed.last!
  guard let value = Double(trimmed.dropLast()), value > 0 else { return nil }

  switch suffix {
  case "m": return value * 60
  case "h": return value * 3600
  case "d": return value * 86400
  default: return nil
  }
}

// MARK: - JSON Output Types

struct PluginOutput: Encodable {
  let value: String
  let icon: String?
  let hidden: Bool
  let variables: [String: String]
  let items: [MenuItem]
}

enum MenuItem: Encodable {
  case header(String)
  case separator
  case item(label: String, icon: String? = nil, command: String? = nil)
  case check(label: String, checked: Bool, command: String)

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .header(let text):
      try container.encode(text, forKey: .header)
    case .separator:
      try container.encode(true, forKey: .separator)
    case .item(let label, let icon, let command):
      try container.encode(label, forKey: .label)
      if let icon { try container.encode(icon, forKey: .icon) }
      if let command { try container.encode(command, forKey: .command) }
    case .check(let label, let checked, let command):
      try container.encode(label, forKey: .check)
      try container.encode(checked, forKey: .checked)
      try container.encode(command, forKey: .command)
    }
  }

  private enum CodingKeys: String, CodingKey {
    case header, separator, label, icon, command, check, checked
  }
}

// MARK: - Helpers

func truncate(_ string: String, maxChars: Int) -> String {
  guard maxChars > 0, string.count > maxChars else { return string }
  return String(string.prefix(maxChars)) + "..."
}

/// Shell-quote a string for safe embedding in a command.
func shellQuote(_ s: String) -> String {
  "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// Apply template variable substitution to a format string.
func applyFormat(_ format: String, variables: [String: String]) -> String {
  var result = format
  for (key, value) in variables {
    result = result.replacingOccurrences(of: "{\(key)}", with: value)
  }
  return result
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

/// Fetch incomplete reminders matching the configured lists.
func fetchIncomplete(
  store: EKEventStore, listConfigs: [ListConfig]
) -> [EKReminder] {
  let allCalendars = store.calendars(for: .reminder)
  let listNames = Set(listConfigs.map { $0.name })
  let calendars = allCalendars.filter { listNames.contains($0.title) }
  guard !calendars.isEmpty else { return [] }

  var configByName: [String: ListConfig] = [:]
  for lc in listConfigs {
    configByName[lc.name] = lc
  }

  let now = Date()
  let predicate = store.predicateForIncompleteReminders(
    withDueDateStarting: nil, ending: nil, calendars: calendars)

  let semaphore = DispatchSemaphore(value: 0)
  var result: [EKReminder] = []

  store.fetchReminders(matching: predicate) { reminders in
    let filtered = (reminders ?? []).filter { reminder in
      guard let lc = configByName[reminder.calendar.title] else { return false }
      guard let dueDate = reminder.dueDateComponents?.date else {
        return lc.undated
      }
      if dueDate < now {
        return lc.overdue
      }
      let endDate = now.addingTimeInterval(lc.lookaheadInterval)
      return dueDate <= endDate
    }

    result = filtered.sorted { a, b in
      switch (a.dueDateComponents?.date, b.dueDateComponents?.date) {
      case let (da?, db?): return da < db
      case (_?, nil): return true
      case (nil, _?): return false
      case (nil, nil): return false
      }
    }
    semaphore.signal()
  }

  semaphore.wait()
  return result
}

/// Fetch recently completed reminders within the retention window.
func fetchCompleted(
  store: EKEventStore, listConfigs: [ListConfig]
) -> [EKReminder] {
  let maxRetention = listConfigs.map { $0.retentionInterval }.max() ?? 0
  guard maxRetention > 0 else { return [] }

  let allCalendars = store.calendars(for: .reminder)
  let listNames = Set(listConfigs.map { $0.name })
  let calendars = allCalendars.filter { listNames.contains($0.title) }
  guard !calendars.isEmpty else { return [] }

  var configByName: [String: ListConfig] = [:]
  for lc in listConfigs {
    configByName[lc.name] = lc
  }

  let now = Date()
  let retentionStart = now.addingTimeInterval(-maxRetention)
  let predicate = store.predicateForCompletedReminders(
    withCompletionDateStarting: retentionStart, ending: now, calendars: calendars)

  let semaphore = DispatchSemaphore(value: 0)
  var result: [EKReminder] = []

  store.fetchReminders(matching: predicate) { reminders in
    let filtered = (reminders ?? []).filter { reminder in
      guard let lc = configByName[reminder.calendar.title] else { return false }
      guard lc.retentionInterval > 0 else { return false }
      guard let completionDate = reminder.completionDate else { return false }
      let listRetentionStart = now.addingTimeInterval(-lc.retentionInterval)
      return completionDate >= listRetentionStart
    }

    result = filtered.sorted { a, b in
      switch (a.completionDate, b.completionDate) {
      case let (da?, db?): return da > db
      case (_?, nil): return true
      case (nil, _?): return false
      case (nil, nil): return false
      }
    }
    semaphore.signal()
  }

  semaphore.wait()
  return result
}

/// Find the list config for a reminder by its calendar title.
func listConfig(for reminder: EKReminder, configs: [ListConfig]) -> ListConfig? {
  configs.first { $0.name == reminder.calendar.title }
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

/// Watch for EventKit changes and trigger kantan module refreshes.
/// Runs until stdin closes (kantan process exits) or the process is terminated.
func watchMode() -> Int32 {
  let store = EKEventStore()
  guard ensureAccess(store: store) else {
    fputs("No access to reminders\n", stderr)
    return 1
  }

  let name = moduleName()
  let triggerCmd = "kantan trigger \(shellQuote(name)) refresh"

  // Watch for EKEventStore changes
  NotificationCenter.default.addObserver(
    forName: .EKEventStoreChanged,
    object: store,
    queue: nil
  ) { _ in
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", triggerCmd]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
  }

  // 60-second backup timer for approaching due dates
  // (entering the lookahead window doesn't trigger EKEventStoreChanged)
  let timer = Timer(timeInterval: 60.0, repeats: true) { _ in
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", triggerCmd]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
  }
  RunLoop.main.add(timer, forMode: .common)

  // Run until stdin closes or process is killed.
  // When kantan exits, stdin (the pipe) closes and we exit cleanly.
  DispatchQueue.global().async {
    while true {
      let data = FileHandle.standardInput.availableData
      if data.isEmpty {
        // stdin closed — parent process exited
        exit(0)
      }
    }
  }

  RunLoop.main.run()
  return 0
}

// MARK: - Default Mode: Fetch & Output JSON

func defaultMode() -> Int32 {
  let settings = loadSettings()

  guard !settings.lists.isEmpty else {
    fputs("No lists configured in settings\n", stderr)
    let output = PluginOutput(
      value: "", icon: nil, hidden: true, variables: [:], items: [])
    printJSON(output)
    return 0
  }

  let store = EKEventStore()
  guard ensureAccess(store: store) else {
    let output = PluginOutput(
      value: "", icon: nil, hidden: true, variables: [:], items: [])
    printJSON(output)
    return 0
  }

  let incomplete = fetchIncomplete(store: store, listConfigs: settings.lists)
  let completed = fetchCompleted(store: store, listConfigs: settings.lists)
  let hasReminders = !incomplete.isEmpty

  // Determine displayed reminder (first incomplete)
  let displayedReminder = incomplete.first
  let displayedListConfig: ListConfig? =
    if let r = displayedReminder {
      listConfig(for: r, configs: settings.lists)
    } else {
      settings.lists.first
    }

  let maxChars = displayedListConfig?.maxChars ?? 30
  let title = displayedReminder?.title ?? ""
  let icon = displayedListConfig?.icon
  let listName = displayedReminder?.calendar.title ?? displayedListConfig?.name ?? ""

  // Format due date if available
  let due: String = {
    guard let comps = displayedReminder?.dueDateComponents, let date = comps.date else {
      return ""
    }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
  }()

  // Build menu items
  var items: [MenuItem] = []
  let allItems = incomplete + completed
  let hasMultiple = allItems.count > 1
  let modName = moduleName()

  if hasMultiple {
    for reminder in incomplete {
      let chars = listConfig(for: reminder, configs: settings.lists)?.maxChars ?? 30
      let label = truncate(reminder.title ?? "Untitled", maxChars: chars)
      let id = reminder.calendarItemIdentifier
      let cmd =
        "kantan-plugin-reminders --complete \(shellQuote(id)) && kantan trigger \(shellQuote(modName)) refresh"
      items.append(.check(label: label, checked: false, command: cmd))
    }
    for reminder in completed {
      let chars = listConfig(for: reminder, configs: settings.lists)?.maxChars ?? 30
      let label = truncate(reminder.title ?? "Untitled", maxChars: chars)
      let id = reminder.calendarItemIdentifier
      let cmd =
        "kantan-plugin-reminders --uncomplete \(shellQuote(id)) && kantan trigger \(shellQuote(modName)) refresh"
      items.append(.check(label: label, checked: true, command: cmd))
    }
  } else if hasReminders {
    if let id = displayedReminder?.calendarItemIdentifier {
      let cmd =
        "kantan-plugin-reminders --complete \(shellQuote(id)) && kantan trigger \(shellQuote(modName)) refresh"
      items.append(.item(label: "Complete", command: cmd))
    }
  }

  items.append(.separator)
  items.append(.item(label: "Open Reminders...", icon: nil, command: "open x-apple-reminderkit://"))

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
  if let icon, !icon.isEmpty {
    variables["list_icon"] = icon
  }

  // Apply format string to produce the displayed value
  let value = applyFormat(settings.format, variables: variables)

  let output = PluginOutput(
    value: value,
    icon: icon,
    hidden: !hasReminders,
    variables: variables,
    items: items
  )

  printJSON(output)
  return 0
}

func printJSON(_ output: PluginOutput) {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  guard let data = try? encoder.encode(output) else { return }
  print(String(data: data, encoding: .utf8)!)
}

// MARK: - Main

func main() -> Int32 {
  let args = CommandLine.arguments

  if args.count >= 3, args[1] == "--complete" {
    return completeReminder(id: args[2])
  }

  if args.count >= 3, args[1] == "--uncomplete" {
    return uncompleteReminder(id: args[2])
  }

  if args.count >= 2, args[1] == "--watch" {
    return watchMode()
  }

  return defaultMode()
}

exit(main())
