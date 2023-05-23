import Foundation
import Yaml
import EventKit

struct RemindersConfigFactory: ModuleConfigurationFactory {
    func configuration(from yaml: Yaml) throws -> ModuleConfiguration {
        return try RemindersConfig(yaml: yaml)
    }
}

struct RemindersConfig: ModuleConfiguration {
    var type: String { "reminders" }
    let store = EKEventStore()
    let list: String?
    // TODO: set back once done debugging
    // var redrawInterval: TimeInterval { 60.0 }  // Refresh every minute
    var redrawInterval: TimeInterval { 5.0 }

    func getValue(completion: @escaping (String) -> Void) {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .authorized:
            fetchNextReminder(completion: completion)
        case .notDetermined, .restricted, .denied:
            completion("Access to reminders not granted")
            @unknown default:
                completion("Unknown authorization status for reminders")
        }
    }

    func getIcon() -> String {
        return ""
    }

    private func requestAccess(completion: @escaping (Bool) -> Void) {
        store.requestAccess(to: .reminder) { granted, error in
            if let error = error {
                print("Error requesting access to reminders: \(error)")
            }
            completion(granted)
        }
    }
    
    private func fetchNextReminder(completion: @escaping (String) -> Void) {
        let predicate: NSPredicate
        if let list = list {
            let calendars = store.calendars(for: .reminder).filter { $0.title == list }
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
            completion(nextReminder?.title ?? "No upcoming reminders")
        }
    }

    init() {
        list = "All"
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined:
            store.requestAccess(to: .reminder) { (granted, error) in
                if granted {
                    print("Access to reminders granted")
                } else {
                    print("Access to reminders denied")
                }
            }
        case .authorized:
            print("Access to reminders already granted")
        case .restricted, .denied:
            print("Access to reminders not granted")
            @unknown default:
                print("Unknown authorization status for reminders")
        }
    }

    init(from decoder: Decoder) throws {
        list = "All"
    }

    init(yaml: Yaml) throws {
        let yamlList = yaml["list"].string
        list = yamlList?.isEmpty ?? true ? "All" : yamlList!
    }

    func encode(to encoder: Encoder) throws { }
}
