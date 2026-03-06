import Foundation
import Yaml

struct ClockConfigFactory: ModuleConfigurationFactory {
    func configuration(from yaml: Yaml) throws -> ModuleConfiguration {
        guard let _ = yaml["format"].string else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Unable to decode clock configuration"))
        }
        return try ClockConfig(yaml: yaml)
    }
}

struct ClockConfig: ModuleConfiguration {
    var type: String { "clock" }
    let format: String
    let timezone: String?

    nonisolated(unsafe) private static var _formatters: [String: DateFormatter] = [:]
    private static let _lock = NSLock()

    init(yaml: Yaml) throws {
        guard let format = yaml["format"].string else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Unable to decode clock configuration"))
        }
        self.format = format
        self.timezone = yaml["timezone"].string

        Self.ensureFormatter(format: format, timezone: self.timezone)
    }

    var redrawInterval: TimeInterval { 1.0 }

    func getValue(completion: @escaping @Sendable (String) -> Void) {
        let formatter = Self.cachedFormatter(format: format, timezone: timezone)
        completion(formatter.string(from: Date()))
    }

    func getIcon() -> String {
        return ""
    }

    func getTemplateVariables() -> [String: String] {
        let now = Date()
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "EEEE"
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "d MMMM yyyy"
        if let tz = timezone, let timeZone = TimeZone(identifier: tz) {
            dayFmt.timeZone = timeZone
            dateFmt.timeZone = timeZone
        }
        let formatter = Self.cachedFormatter(format: format, timezone: timezone)
        return [
            "day": dayFmt.string(from: now),
            "date": dateFmt.string(from: now),
            "time": formatter.string(from: now),
        ]
    }

    private static func formatterKey(format: String, timezone: String?) -> String {
        return "\(format)|\(timezone ?? "system")"
    }

    private static func ensureFormatter(format: String, timezone: String?) {
        let key = formatterKey(format: format, timezone: timezone)
        _lock.lock()
        defer { _lock.unlock() }
        guard _formatters[key] == nil else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = format
        if let tz = timezone, let timeZone = TimeZone(identifier: tz) {
            formatter.timeZone = timeZone
        }
        _formatters[key] = formatter
    }

    private static func cachedFormatter(format: String, timezone: String?) -> DateFormatter {
        let key = formatterKey(format: format, timezone: timezone)
        _lock.lock()
        defer { _lock.unlock() }
        return _formatters[key]!
    }
}
