import AppKit
import Foundation
import Yaml
@preconcurrency import EventKit

struct RemindersConfigFactory: ModuleConfigurationFactory {
    func configuration(from yaml: Yaml, configDir: String?) throws -> ModuleConfiguration {
        return try RemindersConfig(yaml: yaml)
    }
}

/// Parses a duration string like "10m", "12h", "2d" into seconds.
/// Returns nil for invalid input.
private func parseDuration(_ string: String) -> TimeInterval? {
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

/// Truncates a string to `maxChars` characters, appending "..." if truncated.
private func truncate(_ string: String, maxChars: Int) -> String {
    guard maxChars > 0, string.count > maxChars else { return string }
    return String(string.prefix(maxChars)) + "..."
}

/// Per-list configuration for the reminders module.
struct ReminderListConfig: Sendable {
    let name: String
    let icon: String
    let lookaheadInterval: TimeInterval
    let showOverdue: Bool
    let showUndated: Bool
    let completedRetention: TimeInterval
    let maxChars: Int

    init(yaml: Yaml) throws {
        guard let name = yaml["name"].string, !name.isEmpty else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "ReminderListConfig requires a 'name' field"
                ))
        }
        self.name = name
        self.icon = yaml["icon"].string ?? ""

        if let lookaheadStr = yaml["lookahead"].string,
           let interval = parseDuration(lookaheadStr) {
            self.lookaheadInterval = interval
        } else {
            self.lookaheadInterval = 600  // 10 minutes
        }

        self.showOverdue = yaml["overdue"].bool ?? true
        self.showUndated = yaml["undated"].bool ?? false

        if let retentionStr = yaml["completedRetention"].string,
           let interval = parseDuration(retentionStr) {
            self.completedRetention = interval
        } else {
            self.completedRetention = 0
        }

        self.maxChars = yaml["maxChars"].int ?? 30
    }
}

/// Event-driven reminders module using EKEventStoreChanged notification.
/// Fires instantly when reminders are added, completed, or deleted.
/// Keeps a 60s poll for approaching due dates (a reminder entering the
/// lookahead window does not trigger a store change notification).
final class RemindersConfig: ModuleConfiguration, EventDrivenModule, @unchecked Sendable {
    var type: String { "reminders" }
    let listConfigs: [ReminderListConfig]

    var redrawInterval: TimeInterval { 0 }

    nonisolated(unsafe) private var onChange: (@Sendable () -> Void)?
    nonisolated(unsafe) private var dueDateTimer: Timer?
    nonisolated(unsafe) private var storeObserver: NSObjectProtocol?
    nonisolated(unsafe) private var eventStore: EKEventStore?
    nonisolated(unsafe) private var _hasReminders: Bool = true
    nonisolated(unsafe) private var _cachedIncomplete: [EKReminder] = []
    nonisolated(unsafe) private var _cachedCompleted: [EKReminder] = []
    nonisolated(unsafe) private var _displayedReminderID: String?

    init(yaml: Yaml) throws {
        guard let listsYaml = yaml["lists"].array, !listsYaml.isEmpty else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "RemindersConfig requires a non-empty 'lists' array"
                ))
        }

        self.listConfigs = try listsYaml.map { try ReminderListConfig(yaml: $0) }
    }

    required init(from decoder: Decoder) throws {
        listConfigs = []
    }

    func encode(to encoder: Encoder) throws {}

    // MARK: - List Config Lookup

    /// Find the list config matching a reminder's calendar title.
    private func listConfig(for reminder: EKReminder) -> ReminderListConfig? {
        let calendarTitle = reminder.calendar.title
        return listConfigs.first { $0.name == calendarTitle }
    }

    /// Find the list config for the currently displayed reminder.
    private func displayedListConfig() -> ReminderListConfig? {
        guard let id = _displayedReminderID,
              let reminder = _cachedIncomplete.first(where: { $0.calendarItemIdentifier == id }) else {
            return listConfigs.first
        }
        return listConfig(for: reminder) ?? listConfigs.first
    }

    // MARK: - Lazy Event Store

    private func getOrCreateStore() -> EKEventStore {
        if let store = eventStore {
            return store
        }
        let store = EKEventStore()
        eventStore = store
        return store
    }

    // MARK: - EventDrivenModule

    func startObserving(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange

        let store = getOrCreateStore()

        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: nil
        ) { [weak self] _ in
            self?.onChange?()
        }

        dueDateTimer = Timer.scheduledTimer(
            withTimeInterval: 60.0,
            repeats: true
        ) { [weak self] _ in
            self?.onChange?()
        }
    }

    func stopObserving() {
        if let observer = storeObserver {
            NotificationCenter.default.removeObserver(observer)
            storeObserver = nil
        }
        dueDateTimer?.invalidate()
        dueDateTimer = nil
        onChange = nil
    }

    // MARK: - ModuleConfiguration

    func shouldDisplay() -> Bool {
        _hasReminders
    }

    func getValue(completion: @escaping @Sendable (String) -> Void) {
        let store = getOrCreateStore()
        let configs = self.listConfigs

        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .authorized:
            Self.fetchAllReminders(
                store: store,
                listConfigs: configs
            ) { [weak self] incomplete, completed in
                self?.updateCache(incomplete: incomplete, completed: completed)
                let title = incomplete.first?.title ?? ""
                let chars = self?.displayedListConfig()?.maxChars ?? 30
                completion(truncate(title, maxChars: chars))
            }
        case .notDetermined:
            store.requestFullAccessToReminders { [weak self] granted, error in
                if let error = error {
                    print("Error requesting access to reminders: \(error)")
                }
                if granted {
                    Self.fetchAllReminders(
                        store: store,
                        listConfigs: configs
                    ) { [weak self] incomplete, completed in
                        self?.updateCache(incomplete: incomplete, completed: completed)
                        let title = incomplete.first?.title ?? ""
                        let chars = self?.displayedListConfig()?.maxChars ?? 30
                        completion(truncate(title, maxChars: chars))
                    }
                } else {
                    self?.clearCache()
                    completion("")
                }
            }
        case .restricted, .denied, .writeOnly:
            clearCache()
            completion("")
        @unknown default:
            clearCache()
            completion("")
        }
    }

    func getIcon() -> String {
        return displayedListConfig()?.icon ?? ""
    }

    // MARK: - Completion

    func handleToggle() {
        completeDisplayedReminder()
    }

    private func completeDisplayedReminder() {
        guard let store = eventStore,
              let id = _displayedReminderID,
              let reminder = _cachedIncomplete.first(where: { $0.calendarItemIdentifier == id }) else {
            return
        }
        let retention = listConfig(for: reminder)?.completedRetention ?? 0
        reminder.isCompleted = true
        reminder.completionDate = Date()
        do {
            try store.save(reminder, commit: true)
            _cachedIncomplete.removeAll { $0.calendarItemIdentifier == id }
            if retention > 0 {
                _cachedCompleted.insert(reminder, at: 0)
            }
            _displayedReminderID = _cachedIncomplete.first?.calendarItemIdentifier
            _hasReminders = !_cachedIncomplete.isEmpty
        } catch {
            print("Failed to complete reminder: \(error)")
        }
    }

    private func completeReminder(_ reminder: EKReminder) {
        guard let store = eventStore else { return }
        let retention = listConfig(for: reminder)?.completedRetention ?? 0
        reminder.isCompleted = true
        reminder.completionDate = Date()
        do {
            try store.save(reminder, commit: true)
            _cachedIncomplete.removeAll { $0.calendarItemIdentifier == reminder.calendarItemIdentifier }
            if retention > 0 {
                _cachedCompleted.insert(reminder, at: 0)
            }
            if _cachedIncomplete.isEmpty {
                _hasReminders = false
                _displayedReminderID = nil
            } else {
                _displayedReminderID = _cachedIncomplete.first?.calendarItemIdentifier
            }
        } catch {
            print("Failed to complete reminder: \(error)")
        }
    }

    private func uncompleteReminder(_ reminder: EKReminder) {
        guard let store = eventStore else { return }
        reminder.isCompleted = false
        reminder.completionDate = nil
        do {
            try store.save(reminder, commit: true)
            _cachedCompleted.removeAll { $0.calendarItemIdentifier == reminder.calendarItemIdentifier }
            _cachedIncomplete.insert(reminder, at: 0)
            _hasReminders = true
            _displayedReminderID = _cachedIncomplete.first?.calendarItemIdentifier
        } catch {
            print("Failed to uncomplete reminder: \(error)")
        }
    }

    // MARK: - Menu Descriptors

    func getMenuDescriptors() -> [MenuItemDescriptor]? {
        guard !_cachedIncomplete.isEmpty || !_cachedCompleted.isEmpty else { return nil }

        var descriptors: [MenuItemDescriptor] = []
        let allItems = _cachedIncomplete + _cachedCompleted
        let hasMultiple = allItems.count > 1

        if hasMultiple {
            for reminder in _cachedIncomplete {
                let chars = listConfig(for: reminder)?.maxChars ?? 30
                let title = truncate(reminder.title ?? "Untitled", maxChars: chars)
                let r = reminder
                descriptors.append(.check(title, isChecked: false) { [weak self] completion in
                    self?.completeReminder(r)
                    completion()
                })
            }
            for reminder in _cachedCompleted {
                let chars = listConfig(for: reminder)?.maxChars ?? 30
                let title = truncate(reminder.title ?? "Untitled", maxChars: chars)
                let r = reminder
                descriptors.append(.check(title, isChecked: true) { [weak self] completion in
                    self?.uncompleteReminder(r)
                    completion()
                })
            }
        } else {
            descriptors.append(.item("Complete") { [weak self] in
                self?.completeDisplayedReminder()
            })
        }

        descriptors.append(.separator())
        descriptors.append(.item("Open Reminders...") {
            NSWorkspace.shared.open(URL(string: "x-apple-reminderkit://")!)
        })

        return descriptors
    }

    // MARK: - Cache

    private func updateCache(incomplete: [EKReminder], completed: [EKReminder]) {
        _cachedIncomplete = incomplete
        _cachedCompleted = completed
        _hasReminders = !incomplete.isEmpty
        _displayedReminderID = incomplete.first?.calendarItemIdentifier
    }

    private func clearCache() {
        _cachedIncomplete = []
        _cachedCompleted = []
        _hasReminders = false
        _displayedReminderID = nil
    }

    // MARK: - Fetch

    private static func fetchAllReminders(
        store: EKEventStore,
        listConfigs: [ReminderListConfig],
        completion: @escaping @Sendable ([EKReminder], [EKReminder]) -> Void
    ) {
        let allCalendars = store.calendars(for: .reminder)
        let listNames = Set(listConfigs.map { $0.name })
        let calendars = allCalendars.filter { listNames.contains($0.title) }

        guard !calendars.isEmpty else {
            completion([], [])
            return
        }

        // Build a lookup from calendar title → list config
        var configByName: [String: ReminderListConfig] = [:]
        for lc in listConfigs {
            configByName[lc.name] = lc
        }

        let now = Date()

        // Fetch incomplete reminders across all configured calendars.
        // We use a broad predicate (no end date) and filter per-list afterward,
        // since each list may have different lookahead/overdue/undated settings.
        let incompletePredicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: calendars
        )

        store.fetchReminders(matching: incompletePredicate) { reminders in
            let incomplete = (reminders ?? []).filter { reminder in
                guard let lc = configByName[reminder.calendar.title] else { return false }

                guard let dueDate = reminder.dueDateComponents?.date else {
                    return lc.showUndated
                }
                if dueDate < now {
                    return lc.showOverdue
                }
                let endDate = now.addingTimeInterval(lc.lookaheadInterval)
                return dueDate <= endDate
            }

            let sortedIncomplete = incomplete.sorted { a, b in
                let dateA = a.dueDateComponents?.date
                let dateB = b.dueDateComponents?.date
                switch (dateA, dateB) {
                case let (da?, db?): return da < db
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return false
                }
            }

            // Fetch recently completed reminders if any list has retention > 0
            let maxRetention = listConfigs.map { $0.completedRetention }.max() ?? 0
            guard maxRetention > 0 else {
                completion(sortedIncomplete, [])
                return
            }

            let retentionStart = now.addingTimeInterval(-maxRetention)
            let completedPredicate = store.predicateForCompletedReminders(
                withCompletionDateStarting: retentionStart,
                ending: now,
                calendars: calendars
            )

            store.fetchReminders(matching: completedPredicate) { completedReminders in
                // Filter per-list: only keep completed reminders within their list's retention window
                let filtered = (completedReminders ?? []).filter { reminder in
                    guard let lc = configByName[reminder.calendar.title] else { return false }
                    guard lc.completedRetention > 0 else { return false }
                    guard let completionDate = reminder.completionDate else { return false }
                    let listRetentionStart = now.addingTimeInterval(-lc.completedRetention)
                    return completionDate >= listRetentionStart
                }

                let sortedCompleted = filtered.sorted { a, b in
                    let dateA = a.completionDate
                    let dateB = b.completionDate
                    switch (dateA, dateB) {
                    case let (da?, db?): return da > db
                    case (_?, nil): return true
                    case (nil, _?): return false
                    case (nil, nil): return false
                    }
                }
                completion(sortedIncomplete, sortedCompleted)
            }
        }
    }
}
