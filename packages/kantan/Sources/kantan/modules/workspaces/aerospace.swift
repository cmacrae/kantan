import AppKit

/// AeroSpace workspaces, refreshed by `kantan trigger` from AeroSpace's
/// `exec-on-workspace-change`. Empty while AeroSpace isn't running.
struct AerospaceWorkspaces: WorkspaceProvider {
  static let bundleIdentifier = "bobko.aerospace"
  static let homebrewCLIs = ["/opt/homebrew/bin/aerospace", "/usr/local/bin/aerospace"]

  func workspaces() -> [Workspace] {
    guard let cli = Self.runningCLI(),
      let all = runCommandSync(
        path: cli, arguments: ["list-workspaces", "--all", "--json"],
        timeout: windowManagerCLITimeout),
      let focused = runCommandSync(
        path: cli, arguments: ["list-workspaces", "--focused", "--json"],
        timeout: windowManagerCLITimeout)
    else {
      return []
    }
    return Self.parse(all: all, focused: focused)
  }

  var canActivate: Bool { true }

  func activate(_ target: WorkspaceTarget) {
    guard let cli = Self.runningCLI(), let arguments = Self.arguments(for: target) else { return }
    _ = runCommandSync(path: cli, arguments: arguments, timeout: windowManagerCLITimeout)
  }

  /// The `aerospace` arguments that switch to `target`, by workspace name.
  /// AeroSpace reports no scroll, so never a window.
  static func arguments(for target: WorkspaceTarget) -> [String]? {
    guard case .workspace(_, let label) = target else { return nil }
    return ["workspace", label]
  }

  /// The `aerospace` CLI that shipped with the running AeroSpace.app, so
  /// kantan speaks the running server's protocol. Homebrew keeps the CLI
  /// apart from the app, so its prefixes are checked next, then PATH.
  static func runningCLI() -> String? {
    guard
      let app = NSWorkspace.shared.runningApplications.first(where: {
        $0.bundleIdentifier == bundleIdentifier
      })
    else { return nil }
    let path =
      ProcessInfo.processInfo.environment["PATH"]?
      .split(separator: ":").map { "\($0)/aerospace" } ?? []
    return cli(forApp: app.bundleURL, fallbacks: homebrewCLIs + path)
  }

  /// The first executable among `bin/aerospace` beside `app` (release
  /// archive layout) or one level further up (Nix package layout, where the
  /// app sits in `Applications/`), then `fallbacks`.
  static func cli(forApp app: URL?, fallbacks: [String]) -> String? {
    let beside = app?.deletingLastPathComponent()
    let candidates = [beside, beside?.deletingLastPathComponent()].compactMap {
      $0?.appendingPathComponent("bin/aerospace").path
    }
    return (candidates + fallbacks).first(where: FileManager.default.isExecutableFile(atPath:))
  }

  /// Parses `list-workspaces --json` output, ordering numeric names
  /// numerically ahead of the rest.
  static func parse(all: Data, focused: Data) -> [Workspace] {
    struct AeroWorkspace: Decodable {
      let workspace: String
    }

    let decoder = JSONDecoder()
    guard let allSpaces = try? decoder.decode([AeroWorkspace].self, from: all),
      let focusedSpaces = try? decoder.decode([AeroWorkspace].self, from: focused)
    else {
      return []
    }

    let focusedID = focusedSpaces.first?.workspace
    let sorted = allSpaces.sorted { lhs, rhs in
      let lhsInt = Int(lhs.workspace) ?? Int.max
      let rhsInt = Int(rhs.workspace) ?? Int.max
      if lhsInt != rhsInt { return lhsInt < rhsInt }
      return lhs.workspace < rhs.workspace
    }

    return sorted.enumerated().map { index, space in
      Workspace(index: index, label: space.workspace, isActive: space.workspace == focusedID)
    }
  }
}
