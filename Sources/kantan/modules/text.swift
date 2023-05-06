import Yaml

struct TextConfig: Codable {
    let value: String

    init(yaml: Yaml) throws {
        guard let value = yaml["value"].string else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Unable to decode TextConfig from Yaml"))
        }
        self.value = value
    }
}
