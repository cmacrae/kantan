import AppKit

/// Rift's virtual workspaces for the active display's macOS space,
/// refreshed on each `workspace_changed` event. Empty while Rift isn't
/// running.
final class RiftWorkspaces: WorkspaceProvider {
  nonisolated(unsafe) private var eventStream: EventStreamProcess?

  func workspaces() -> [Workspace] {
    guard let cli = Self.runningCLI(),
      let data = runCommandSync(path: cli, arguments: ["query", "workspaces"])
    else {
      return []
    }
    return Self.parse(data)
  }

  func startObserving(onChange: @escaping @Sendable () -> Void) {
    guard eventStream == nil else { return }
    let stream = EventStreamProcess(
      command: { Self.runningCLI().map { [$0, "subscribe", "mach", "workspace_changed"] } },
      onEvent: onChange)
    eventStream = stream
    stream.start()
  }

  func stopObserving() {
    eventStream?.stop()
    eventStream = nil
  }

  /// The `rift-cli` shipped beside the running `rift`, so kantan always
  /// speaks the running server's protocol and needs nothing on its PATH.
  static func runningCLI() -> String? {
    cli(among: NSWorkspace.shared.runningApplications.map(\.executableURL))
  }

  /// The executable `rift-cli` next to the first `rift` among `executables`.
  static func cli(among executables: [URL?]) -> String? {
    guard let rift = executables.compactMap({ $0 }).first(where: { $0.lastPathComponent == "rift" })
    else { return nil }
    let cli = rift.deletingLastPathComponent().appendingPathComponent("rift-cli").path
    return FileManager.default.isExecutableFile(atPath: cli) ? cli : nil
  }

  /// Parses `rift-cli query workspaces` output, ordered by workspace index
  /// and labelled with each workspace's name.
  static func parse(_ data: Data) -> [Workspace] {
    struct RiftWorkspace: Decodable {
      let index: Int
      let name: String
      let isActive: Bool

      enum CodingKeys: String, CodingKey {
        case index, name
        case isActive = "is_active"
      }
    }

    guard let workspaces = try? JSONDecoder().decode([RiftWorkspace].self, from: data) else {
      return []
    }
    return workspaces.sorted { $0.index < $1.index }.enumerated().map { position, workspace in
      Workspace(index: position, label: workspace.name, isActive: workspace.isActive)
    }
  }
}
