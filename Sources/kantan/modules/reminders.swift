import Foundation
import Yaml
@preconcurrency import EventKit

nonisolated(unsafe) private let sharedEventStore = EKEventStore()

struct RemindersConfigFactory: ModuleConfigurationFactory {
    func configuration(from yaml: Yaml) throws -> ModuleConfiguration {
        return try RemindersConfig(yaml: yaml)
    }
}

struct RemindersConfig: ModuleConfiguration {
    var type: String { "reminders" }
    let lists: [String]?
    let excludeLists: [String]?
    let daysAhead: Int

    var redrawInterval: TimeInterval { 30.0 }

    init(yaml: Yaml) throws {
        if let singleList = yaml["list"].string, !singleList.isEmpty {
            self.lists = [singleList]
        } else if let multipleLists = yaml["lists"].array?.compactMap({ $0.string }), !multipleLists.isEmpty {
            self.lists = multipleLists
        } else {
            self.lists = nil
        }

        if let excludes = yaml["excludeLists"].array?.compactMap({ $0.string }), !excludes.isEmpty {
            self.excludeLists = excludes
        } else {
            self.excludeLists = nil
        }

        self.daysAhead = yaml["daysAhead"].int ?? 7
    }

    init(from decoder: Decoder) throws {
        lists = nil
        excludeLists = nil
        daysAhead = 7
    }

    func encode(to encoder: Encoder) throws { }

    func getValue(completion: @escaping @Sendable (String) -> Void) {
        let store = sharedEventStore
        let allowLists = self.lists
        let denyLists = self.excludeLists
        let days = self.daysAhead

        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .authorized:
            Self.fetchNextReminder(
                store: store,
                allowLists: allowLists,
                denyLists: denyLists,
                daysAhead: days,
                completion: completion
            )
        case .notDetermined:
            store.requestFullAccessToReminders { granted, error in
                if let error = error {
                    print("Error requesting access to reminders: \(error)")
                }
                if granted {
                    Self.fetchNextReminder(
                        store: store,
                        allowLists: allowLists,
                        denyLists: denyLists,
                        daysAhead: days,
                        completion: completion
                    )
                } else {
                    completion("")
                }
            }
        case .restricted, .denied, .writeOnly:
            completion("")
        @unknown default:
            completion("")
        }
    }

    func getIcon() -> String {
        return ""
    }

    private static func fetchNextReminder(
        store: EKEventStore,
        allowLists: [String]?,
        denyLists: [String]?,
        daysAhead: Int,
        completion: @escaping @Sendable (String) -> Void
    ) {
        var calendars = store.calendars(for: .reminder)

        if let allowLists = allowLists {
            calendars = calendars.filter { allowLists.contains($0.title) }
        }

        if let denyLists = denyLists {
            calendars = calendars.filter { !denyLists.contains($0.title) }
        }

        let now = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: daysAhead, to: now)

        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: now,
            ending: endDate,
            calendars: calendars.isEmpty ? nil : calendars
        )

        store.fetchReminders(matching: predicate) { reminders in
            guard let reminders = reminders, !reminders.isEmpty else {
                completion("No upcoming reminders")
                return
            }

            let sorted = reminders
                .compactMap { reminder -> (EKReminder, Date)? in
                    guard let components = reminder.dueDateComponents,
                          let date = components.date else {
                        return nil
                    }
                    return (reminder, date)
                }
                .sorted { $0.1 < $1.1 }

            let value = sorted.first?.0.title ?? "No upcoming reminders"
            completion(value)
        }
    }
}
