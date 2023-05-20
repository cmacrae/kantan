import Foundation
import Yaml

struct CommandConfigFactory: ModuleConfigurationFactory {
    func configuration(from yaml: Yaml) throws -> ModuleConfiguration {
        guard let _ = yaml["command"].string else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Unable to decode CommandConfig from Yaml"))
        }
        return try CommandConfig(yaml: yaml)
    }
}

struct CommandConfig: ModuleConfiguration {
    var type: String { "command" }
    let command: String
    var output: String = ""
    let launchPath: String
    let launchArgs: [String]

    init(yaml: Yaml) throws {
        guard let command = yaml["command"].string else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Unable to decode CommandConfig from Yaml"))
        }
        self.command = command
        self.launchPath = yaml["launcher"]["path"].string ?? "/bin/sh"
        self.launchArgs = yaml["launcher"]["args"].array?.compactMap { $0.string } ?? ["-c"]
    }

    var redrawInterval: TimeInterval { 1.0 }

    // TODO: blocking implementation - see below
    func getValue(completion: @escaping (String) -> Void) {
        let result = self.executeCommand()
        completion(result)
    }

    // FIXME: non-blocking implementation, however due to race conditions
    //        in current rendering implementation, no otput is displayed
    // func getValue(completion: @escaping (String) -> Void) {
    // //     DispatchQueue.global(qos: .background).async {
    //     DispatchQueue.global(qos: .userInitiated).async {
    //         let result = self.executeCommand()
    //         DispatchQueue.main.async {
    //             completion(result)
    //         }
    //     }
    // }

    func getIcon() -> String {
        return ""
    }

    private func executeCommand() -> String {
        let process = Process()
        process.launchPath = self.launchPath
        process.arguments = self.launchArgs + [self.command]

        let outpipe = Pipe()
        process.standardOutput = outpipe
        process.standardError = outpipe

        process.launch()

        let outdata = outpipe.fileHandleForReading.readDataToEndOfFile()
        if var string = String(data: outdata, encoding: .utf8) {
            string = string.trimmingCharacters(in: .newlines)
            return string
        } else {
            return "exec failed"
        }
    }
}

