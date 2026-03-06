import Foundation
import Yaml
@preconcurrency import EventKit

struct RemindersConfigFactory: ModuleConfigurationFactory {
    func configuration(from yaml: Yaml) throws -> ModuleConfiguration {
        return try RemindersConfig(yaml: yaml)
    }
}

struct RemindersConfig: ModuleConfiguration {
    var type: String { "reminders" }
    let list: String?
    var redrawInterval: TimeInterval { 5.0 }

    // Store the last fetched value for synchronous access during drawing
    nonisolated(unsafe) static var _lastFetchedValues: [String: String] = [:]

    var lastFetchedValue: String {
        return RemindersConfig._lastFetchedValues[list ?? "All"] ?? "Loading..."
    }

    func getValue(completion: @escaping @Sendable (String) -> Void) {
        let store = EKEventStore()
        let listName = self.list

        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .authorized:
            fetchNextReminder(store: store, listName: listName, completion: completion)
        case .notDetermined:
            store.requestFullAccessToReminders { granted, error in
                if let error = error {
                    print("Error requesting access to reminders: \(error)")
                }
                if granted {
                    let freshStore = EKEventStore()
                    self.fetchNextReminder(store: freshStore, listName: listName, completion: completion)
                } else {
                    completion("Access to reminders denied")
                }
            }
        case .restricted, .denied, .writeOnly:
            completion("Access to reminders not granted")
        @unknown default:
            completion("Unknown authorization status for reminders")
        }
    }

    func getIcon() -> String {
        return ""
    }

    private func fetchNextReminder(store: EKEventStore, listName: String?, completion: @escaping @Sendable (String) -> Void) {
        let predicate: NSPredicate
        if let listName = listName {
            let calendars = store.calendars(for: .reminder).filter { $0.title == listName }
            predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)
        } else {
            predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        }
        store.fetchReminders(matching: predicate) { reminders in
            guard let reminders = reminders else {
                completion("Failed to fetch reminders")
                return
            }
            let nextReminder = reminders
              .filter { $0.dueDateComponents != nil }
              .sorted { $0.dueDateComponents!.date! < $1.dueDateComponents!.date! }
              .first
            let value = nextReminder?.title ?? "No upcoming reminders"
            RemindersConfig._lastFetchedValues[listName ?? "All"] = value
            completion(value)
        }
    }

    init(yaml: Yaml) throws {
        let yamlList = yaml["list"].string
        list = yamlList?.isEmpty ?? true ? "All" : yamlList!
    }

    init(from decoder: Decoder) throws {
        list = "All"
    }

    func encode(to encoder: Encoder) throws { }
}
