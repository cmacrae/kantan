import AppKit

/// Rift's virtual workspaces for the active display's macOS space,
/// refreshed on each `workspace_changed` event. Empty while Rift isn't
/// running.
///
/// With `scrolling`, it also reports which window is selected in the active
/// workspace's scrolling layout, and refreshes on the window, focus and
/// layout events that change the scroll.
final class RiftWorkspaces: WorkspaceProvider {
  /// Longest delay before a burst of scroll events refreshes the module;
  /// scrolling the strip by gesture reports a layout change per frame.
  static let scrollEventCoalescing: TimeInterval = 0.05

  let scrolling: Bool
  nonisolated(unsafe) private var eventStream: EventStreamProcess?

  init(scrolling: Bool = false) {
    self.scrolling = scrolling
  }

  func workspaces() -> [Workspace] {
    guard let cli = Self.runningCLI(),
      let data = runCommandSync(path: cli, arguments: ["query", "workspaces"])
    else {
      return []
    }
    var workspaces = Self.parse(data)
    // The layout's selection stays put while focus is on another display
    // or a floating window, unlike the focused window.
    if scrolling,
      let active = workspaces.firstIndex(where: { $0.isActive && $0.scroll != nil }),
      let layout = runCommandSync(path: cli, arguments: ["query", "layout"]),
      let selected = Self.selectedWindow(in: layout)
    {
      workspaces[active].selectWindow(selected)
    }
    return workspaces
  }

  func startObserving(onChange: @escaping @Sendable () -> Void) {
    guard eventStream == nil else { return }
    let event = scrolling ? "*" : "workspace_changed"
    let stream = EventStreamProcess(
      command: { Self.runningCLI().map { [$0, "subscribe", "mach", event] } },
      coalescing: scrolling ? Self.scrollEventCoalescing : 0,
      accepts: scrolling ? Self.affectsScroll : nil,
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

  private struct WindowID: Decodable {
    let idx: Int
    let pid: Int

    var key: String { "\(pid)-\(idx)" }
  }

  /// Parses `rift-cli query workspaces` output, ordered by workspace index
  /// and labelled with each workspace's name. Scrolling workspaces carry
  /// their tiled windows in strip order, with the focused one selected.
  static func parse(_ data: Data) -> [Workspace] {
    struct RiftWindow: Decodable {
      struct Position: Decodable {
        let column: Int
        let row: Int
      }

      let id: WindowID
      let appName: String?
      let bundleID: String?
      let isFloating: Bool?
      let isFocused: Bool?
      let layoutPosition: Position?

      enum CodingKeys: String, CodingKey {
        case id
        case appName = "app_name"
        case bundleID = "bundle_id"
        case isFloating = "is_floating"
        case isFocused = "is_focused"
        case layoutPosition = "layout_position"
      }
    }

    struct RiftWorkspace: Decodable {
      let index: Int
      let name: String
      let isActive: Bool
      let layoutMode: String?
      let windowCount: Int?
      let windows: [RiftWindow]?

      enum CodingKeys: String, CodingKey {
        case index, name, windows
        case isActive = "is_active"
        case layoutMode = "layout_mode"
        case windowCount = "window_count"
      }

      var scroll: [ScrollWindow]? {
        guard layoutMode == "scrolling" else { return nil }
        let tiled = (windows ?? []).compactMap { window -> (RiftWindow, RiftWindow.Position)? in
          guard window.isFloating != true, let position = window.layoutPosition else { return nil }
          return (window, position)
        }
        let ordered = tiled.sorted { ($0.1.column, $0.1.row) < ($1.1.column, $1.1.row) }
        return ordered.map { window, _ in
          ScrollWindow(
            id: window.id.key, app: window.appName ?? "",
            bundleIdentifier: window.bundleID, isSelected: window.isFocused == true)
        }
      }
    }

    guard let workspaces = try? JSONDecoder().decode([RiftWorkspace].self, from: data) else {
      return []
    }
    return workspaces.sorted { $0.index < $1.index }.enumerated().map { position, workspace in
      Workspace(
        index: position, label: workspace.name, isActive: workspace.isActive,
        hasWindows: (workspace.windowCount ?? workspace.windows?.count ?? 0) > 0,
        scroll: workspace.scroll)
    }
  }

  /// The selected window in `rift-cli query layout` output.
  static func selectedWindow(in data: Data) -> String? {
    struct Layout: Decodable {
      let selectedWindow: WindowID?

      enum CodingKeys: String, CodingKey {
        case selectedWindow = "selected_window"
      }
    }
    return (try? JSONDecoder().decode(Layout.self, from: data))?.selectedWindow?.key
  }

  /// Whether an event from a `*` subscription can change the workspaces or
  /// the active scroll. Title and stack changes can't, and layout changes
  /// only matter in a scrolling layout, where they reorder its windows.
  @Sendable static func affectsScroll(_ event: Data) -> Bool {
    guard let object = try? JSONSerialization.jsonObject(with: event) as? [String: Any],
      let type = object["type"] as? String
    else { return false }
    switch type {
    case "workspace_changed", "windows_changed", "focused_window_changed":
      return true
    case "layout_changed", "selection_changed":
      return (object["layout"] as? [String: Any])?["mode"] as? String == "scrolling"
    default:
      return false
    }
  }
}
