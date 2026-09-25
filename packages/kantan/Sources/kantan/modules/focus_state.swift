import Foundation

/// A Focus mode as described by `ModeConfigurations.json`.
struct FocusMode: Equatable, Sendable {
  /// e.g. `com.apple.focus.mindfulness`
  let identifier: String
  /// User-facing name, e.g. `Mindfulness`.
  let name: String
}

/// A recurring window from a mode's enabled schedule trigger.
struct FocusSchedule: Equatable, Sendable {
  let modeIdentifier: String
  /// Minutes after midnight, local time.
  let startMinute: Int
  let endMinute: Int
  /// Days the window starts on: bit 0 = Monday … bit 6 = Sunday.
  let weekdays: Int

  /// Start of the window containing `date`, or `nil` when `date` falls
  /// outside every occurrence. Windows whose end precedes their start run
  /// overnight into the following day.
  func activeWindowStart(at date: Date, calendar: Calendar) -> Date? {
    let today = calendar.startOfDay(for: date)
    for dayOffset in [0, -1] {
      guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today),
        startsOn(day, calendar: calendar),
        let start = calendar.date(
          bySettingHour: startMinute / 60, minute: startMinute % 60, second: 0, of: day),
        let endDay = calendar.date(
          byAdding: .day, value: endMinute > startMinute ? 0 : 1, to: day),
        let end = calendar.date(
          bySettingHour: endMinute / 60, minute: endMinute % 60, second: 0, of: endDay)
      else { continue }
      if start <= date && date < end { return start }
    }
    return nil
  }

  private func startsOn(_ day: Date, calendar: Calendar) -> Bool {
    // Calendar weekdays run Sunday = 1 … Saturday = 7.
    let bit = (calendar.component(.weekday, from: day) + 5) % 7
    return weekdays & (1 << bit) != 0
  }
}

/// A Focus activation persisted in `Assertions.json`.
struct FocusAssertion: Equatable, Sendable {
  let modeIdentifier: String
  let start: Date
}

/// Focus state reconstructed from the Do Not Disturb database that
/// `donotdisturbd` keeps in `~/Library/DoNotDisturb/DB`, readable with
/// Full Disk Access.
///
/// Explicit activations (Control Centre, Shortcuts, Sleep, Driving and smart
/// triggers) are persisted as assertions naming their mode. Scheduled Focus
/// is held only in the daemon's memory, so it is derived from each mode's
/// enabled schedule triggers. A user state change is recorded as an
/// invalidation request matching any assertion, and ends scheduled Focus
/// until its next window starts. The most recently started candidate wins.
struct FocusDatabase: Equatable, Sendable {
  var modes: [String: FocusMode]
  var schedules: [FocusSchedule]
  var assertions: [FocusAssertion]
  /// Latest invalidation request that cleared every assertion.
  var lastStateChange: Date?

  static let directory = URL(fileURLWithPath: NSHomeDirectory())
    .appendingPathComponent("Library/DoNotDisturb/DB")

  /// `enabledSetting` value marking a trigger as enabled.
  private static let enabledSetting = 2

  /// Load both database files, or `nil` when either is missing or unreadable.
  static func load(from directory: URL = directory) -> FocusDatabase? {
    guard
      let assertions = try? Data(contentsOf: directory.appendingPathComponent("Assertions.json")),
      let modes = try? Data(
        contentsOf: directory.appendingPathComponent("ModeConfigurations.json"))
    else { return nil }
    return FocusDatabase(assertionsJSON: assertions, modeConfigurationsJSON: modes)
  }

  init(
    modes: [String: FocusMode], schedules: [FocusSchedule], assertions: [FocusAssertion],
    lastStateChange: Date?
  ) {
    self.modes = modes
    self.schedules = schedules
    self.assertions = assertions
    self.lastStateChange = lastStateChange
  }

  init?(assertionsJSON: Data, modeConfigurationsJSON: Data) {
    let decoder = JSONDecoder()
    guard let store = try? decoder.decode(AssertionStore.self, from: assertionsJSON),
      let configs = try? decoder.decode(ModeConfigurationStore.self, from: modeConfigurationsJSON)
    else { return nil }

    let entries = store.data
    assertions = entries.flatMap { $0.storeAssertionRecords ?? [] }.compactMap { record in
      guard let mode = record.assertionDetails?.assertionDetailsModeIdentifier,
        let start = record.assertionStartDateTimestamp
      else { return nil }
      return FocusAssertion(
        modeIdentifier: mode, start: Date(timeIntervalSinceReferenceDate: start))
    }
    lastStateChange = entries.flatMap { $0.storeInvalidationRequestRecords ?? [] }
      .filter { $0.invalidationRequestPredicate?.invalidationPredicateType == "any" }
      .compactMap { $0.invalidationRequestDateTimestamp }
      .max()
      .map { Date(timeIntervalSinceReferenceDate: $0) }

    var modes: [String: FocusMode] = [:]
    var schedules: [FocusSchedule] = []
    for (key, config) in configs.data.flatMap({ $0.modeConfigurations }) {
      let identifier = config.mode.modeIdentifier ?? key
      modes[identifier] = FocusMode(identifier: identifier, name: config.mode.name ?? identifier)
      for trigger in config.triggers?.triggers ?? [] {
        guard trigger.`class` == "DNDModeConfigurationScheduleTrigger",
          trigger.enabledSetting == Self.enabledSetting,
          let startHour = trigger.timePeriodStartTimeHour,
          let endHour = trigger.timePeriodEndTimeHour,
          let weekdays = trigger.timePeriodWeekdays
        else { continue }
        schedules.append(
          FocusSchedule(
            modeIdentifier: identifier,
            startMinute: startHour * 60 + (trigger.timePeriodStartTimeMinute ?? 0),
            endMinute: endHour * 60 + (trigger.timePeriodEndTimeMinute ?? 0),
            weekdays: weekdays))
      }
    }
    self.modes = modes
    self.schedules = schedules
  }

  /// The Focus mode active at `date`, or `nil` when Focus is off.
  func activeMode(at date: Date, calendar: Calendar = .current) -> FocusMode? {
    let asserted = assertions.map { (mode: $0.modeIdentifier, start: $0.start) }
    let scheduled = schedules.compactMap { schedule -> (mode: String, start: Date)? in
      guard let start = schedule.activeWindowStart(at: date, calendar: calendar) else {
        return nil
      }
      if let lastStateChange, lastStateChange >= start { return nil }
      return (schedule.modeIdentifier, start)
    }
    guard
      let winner = (asserted + scheduled).filter({ $0.start <= date })
        .max(by: { $0.start < $1.start })
    else { return nil }
    return modes[winner.mode] ?? FocusMode(identifier: winner.mode, name: winner.mode)
  }
}

// MARK: - Database Schema

/// `Assertions.json`: `{"data": [{storeAssertionRecords, storeInvalidationRequestRecords}]}`.
private struct AssertionStore: Decodable {
  struct Entry: Decodable {
    let storeAssertionRecords: [Record]?
    let storeInvalidationRequestRecords: [InvalidationRequest]?
  }
  struct Record: Decodable {
    struct Details: Decodable {
      let assertionDetailsModeIdentifier: String?
    }
    let assertionStartDateTimestamp: Double?
    let assertionDetails: Details?
  }
  struct InvalidationRequest: Decodable {
    struct Predicate: Decodable {
      let invalidationPredicateType: String?
    }
    let invalidationRequestDateTimestamp: Double?
    let invalidationRequestPredicate: Predicate?
  }
  let data: [Entry]
}

/// `ModeConfigurations.json`: `{"data": [{modeConfigurations: {<id>: {mode, triggers}}}]}`.
private struct ModeConfigurationStore: Decodable {
  struct Entry: Decodable {
    let modeConfigurations: [String: Configuration]
  }
  struct Configuration: Decodable {
    let mode: Mode
    let triggers: Triggers?
  }
  struct Mode: Decodable {
    let name: String?
    let modeIdentifier: String?
  }
  struct Triggers: Decodable {
    let triggers: [Trigger]
  }
  struct Trigger: Decodable {
    let `class`: String?
    let enabledSetting: Int?
    let timePeriodStartTimeHour: Int?
    let timePeriodStartTimeMinute: Int?
    let timePeriodEndTimeHour: Int?
    let timePeriodEndTimeMinute: Int?
    let timePeriodWeekdays: Int?
  }
  let data: [Entry]
}
