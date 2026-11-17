import Foundation

struct ClockConfigFactory: ModuleConfigurationFactory {
  func configuration(from yaml: Yaml, configDir: String?, theme: ThemeConfig?) throws
    -> ModuleConfiguration
  {
    return try ClockConfig(yaml: yaml)
  }
}

struct ClockConfig: ModuleConfiguration {
  var type: String { "clock" }
  let format: String
  let timezone: String?
  /// Variable name → format, each exposed as a template variable.
  let formats: [String: String]

  nonisolated(unsafe) private static var _formatters: [String: DateFormatter] = [:]
  private static let _lock = NSLock()

  /// Stands in for an ordinal day's suffix in a DateFormatter pattern until
  /// the day is known.
  private static let ordinalMarker = "\u{E000}"

  init(yaml: Yaml) throws {
    guard let format = yaml["format"].string else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: [], debugDescription: "Unable to decode clock configuration"))
    }
    self.format = format
    self.timezone = yaml["timezone"].string
    var formats: [String: String] = [:]
    for (key, value) in yaml["formats"].dictionary ?? [:] {
      if let name = key.string, let pattern = value.string {
        formats[name] = pattern
      }
    }
    self.formats = formats
  }

  var redrawInterval: TimeInterval { 1.0 }

  func getValue(completion: @escaping @Sendable (String) -> Void) {
    completion(Self.string(from: Date(), format: format, timezone: timezone))
  }

  func getTemplateVariables() -> [String: String] {
    let now = Date()
    return formats.mapValues { Self.string(from: now, format: $0, timezone: timezone) }
  }

  /// `date` in `format`, a DateFormatter pattern in which `do` is the day of
  /// the month with its English ordinal suffix (`1st`, `2nd`, `16th`).
  /// Names are written in `locale`, or the system's when it is nil.
  static func string(
    from date: Date, format: String, timezone: String?, locale: Locale? = nil
  ) -> String {
    let formatter = cachedFormatter(format: format, timezone: timezone, locale: locale)
    let text = formatter.string(from: date)
    guard text.contains(ordinalMarker) else { return text }
    let day = formatter.calendar.dateComponents(in: formatter.timeZone, from: date).day ?? 0
    return text.replacingOccurrences(of: ordinalMarker, with: ordinalSuffix(for: day))
  }

  /// English ordinal suffix for `day`.
  static func ordinalSuffix(for day: Int) -> String {
    if (11...13).contains(day % 100) { return "th" }
    switch day % 10 {
    case 1: return "st"
    case 2: return "nd"
    case 3: return "rd"
    default: return "th"
    }
  }

  /// `format` with each unquoted `do` replaced by the day and a quoted
  /// ordinal marker, ready for DateFormatter.
  static func dateFormatterPattern(for format: String) -> String {
    let chars = Array(format)
    var result = ""
    var quoted = false
    var i = 0
    while i < chars.count {
      let c = chars[i]
      if c == "'" {
        quoted.toggle()
        result.append(c)
        i += 1
        continue
      }
      if !quoted, c.isLetter {
        var end = i
        while end < chars.count, chars[end] == c { end += 1 }
        let isLoneD = c == "d" && end - i == 1
        if isLoneD, end < chars.count, chars[end] == "o",
          end + 1 == chars.count || chars[end + 1] != "o"
        {
          result += "d'\(ordinalMarker)'"
          i = end + 1
          continue
        }
        result += String(chars[i..<end])
        i = end
        continue
      }
      result.append(c)
      i += 1
    }
    return result
  }

  private static func cachedFormatter(format: String, timezone: String?, locale: Locale?)
    -> DateFormatter
  {
    let key = "\(format)|\(timezone ?? "system")|\(locale?.identifier ?? "system")"
    _lock.lock()
    defer { _lock.unlock() }
    if let formatter = _formatters[key] { return formatter }
    let formatter = DateFormatter()
    if let locale { formatter.locale = locale }
    formatter.dateFormat = dateFormatterPattern(for: format)
    if let timeZone = timezone.flatMap(TimeZone.init(identifier:)) {
      formatter.timeZone = timeZone
    }
    _formatters[key] = formatter
    return formatter
  }
}
