import Foundation
import Yaml

struct TextConfigFactory: ModuleConfigurationFactory {
  func configuration(from yaml: Yaml, configDir: String?) throws -> ModuleConfiguration {
    return try TextConfig(yaml: yaml)
  }
}

struct TextConfig: ModuleConfiguration {
  var type: String { "text" }
  let value: String

  init(yaml: Yaml) throws {
    guard let value = yaml["value"].string else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: [], debugDescription: "Unable to decode TextConfig from Yaml"))
    }
    self.value = value
  }

  // Static value — no polling needed. CLI triggers can still update
  // via BarViewModel.handleEvent(), and EventObserver.refreshAll()
  // will call update() on wake/space-change.
  var redrawInterval: TimeInterval { noPoll }

  func getValue(completion: @escaping @Sendable (String) -> Void) {
    completion(self.value)
  }
}
