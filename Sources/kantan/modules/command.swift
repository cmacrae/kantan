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

    func getValue(completion: @escaping @Sendable (String) -> Void) {
        let cmd = self.command
        let path = self.launchPath
        let args = self.launchArgs
        DispatchQueue.global(qos: .background).async {
            let result = executeCommand(command: cmd, launchPath: path, launchArgs: args)
            completion(result)
        }
    }

    func getValueSync() -> String {
        return executeCommand(command: command, launchPath: launchPath, launchArgs: launchArgs)
    }

    func getIcon() -> String {
        return ""
    }
}

private func executeCommand(command: String, launchPath: String, launchArgs: [String]) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = launchArgs + [command]

    let outpipe = Pipe()
    process.standardOutput = outpipe
    process.standardError = outpipe

    do {
        try process.run()
    } catch {
        return "exec failed"
    }

    let outdata = outpipe.fileHandleForReading.readDataToEndOfFile()
    if var string = String(data: outdata, encoding: .utf8) {
        string = string.trimmingCharacters(in: .newlines)
        return string
    } else {
        return "exec failed"
    }
}
