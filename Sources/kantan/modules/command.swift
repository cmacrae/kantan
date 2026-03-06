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
    let timeout: TimeInterval

    init(yaml: Yaml) throws {
        guard let command = yaml["command"].string else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Unable to decode CommandConfig from Yaml"))
        }
        self.command = command
        self.launchPath = yaml["launcher"]["path"].string ?? "/bin/sh"
        self.launchArgs = yaml["launcher"]["args"].array?.compactMap { $0.string } ?? ["-c"]
        self.timeout = yaml["timeout"].double ?? 10.0
    }

    var redrawInterval: TimeInterval { 1.0 }

    func getValue(completion: @escaping @Sendable (String) -> Void) {
        let cmd = self.command
        let path = self.launchPath
        let args = self.launchArgs
        let timeoutInterval = self.timeout

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.executeCommand(
                command: cmd,
                launchPath: path,
                launchArgs: args,
                timeout: timeoutInterval
            )
            completion(result)
        }
    }

    func getIcon() -> String {
        return ""
    }

    private static func executeCommand(
        command: String,
        launchPath: String,
        launchArgs: [String],
        timeout: TimeInterval
    ) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = launchArgs + [command]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return ""
        }

        let timeoutWorkItem = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(
            deadline: .now() + timeout,
            execute: timeoutWorkItem
        )

        let outdata = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeoutWorkItem.cancel()

        guard process.terminationStatus == 0 else {
            return ""
        }

        if var string = String(data: outdata, encoding: .utf8) {
            string = string.trimmingCharacters(in: .newlines)
            return string
        }

        return ""
    }
}
