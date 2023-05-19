import Foundation
import Yaml

struct TextConfig: ModuleConfiguration {
    var type: String { "text" }
    let value: String

    init(yaml: Yaml) throws {
        guard let value = yaml["value"].string else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Unable to decode TextConfig from Yaml"))
        }
        self.value = value
    }


    var redrawInterval: TimeInterval { 1.0 }

    func getNewValue() -> String {
        return self.value
    }
}
