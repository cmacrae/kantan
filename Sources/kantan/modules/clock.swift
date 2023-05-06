import Foundation
import Yaml

struct ClockConfig: Codable {
    let format: String

    init(yaml: Yaml) throws {
        guard let format = yaml["format"].string else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Unable to decode ClockConfig from Yaml"))
        }
        self.format = format
    }
}

func getClockText(format: String) -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = format
    return dateFormatter.string(from: Date())
}
