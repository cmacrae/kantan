import Foundation

/// Native macOS spaces across all displays. A switch of space refreshes
/// them through EventObserver, on
/// NSWorkspace.activeSpaceDidChangeNotification. macOS says nothing of a
/// space added or removed in Mission Control without a switch, so the
/// spaces there are are read every couple of seconds for that.
struct NativeWorkspaces: WorkspaceProvider {
  /// How often the spaces there are are read, in seconds.
  static let spaceListInterval = 2

  private let spaceList = SpaceListWatch()

  func startObserving(onChange: @escaping @Sendable () -> Void) {
    spaceList.start(every: Self.spaceListInterval, onChange: onChange)
  }

  func stopObserving() {
    spaceList.stop()
  }

  /// The identifier of every space in `CGSCopyManagedDisplaySpaces`
  /// output, display by display. It changes as a space is added, removed or
  /// moved, and not as one becomes current.
  static func spaceIDs(of displaySpaces: [[String: Any]]) -> [[Int]] {
    displaySpaces.map { display in
      (display["Spaces"] as? [[String: Any]] ?? []).compactMap { $0["id64"] as? Int }
    }
  }

  func workspaces() -> [Workspace] {
    let cid = CGSMainConnectionID()
    guard
      let displaySpaces = CGSCopyManagedDisplaySpaces(cid)
        as? [[String: Any]]
    else {
      return []
    }
    return Self.workspaces(of: displaySpaces, activeSpace: Int(CGSGetActiveSpace(cid)))
  }

  /// The workspaces in `CGSCopyManagedDisplaySpaces` output. Each display's
  /// current space is active, or `activeSpace` for a display that names none.
  static func workspaces(of displaySpaces: [[String: Any]], activeSpace: Int) -> [Workspace] {
    var result: [Workspace] = []
    var globalIndex = 0

    for display in displaySpaces {
      guard
        let spaces = display["Spaces"] as? [[String: Any]]
      else {
        continue
      }
      let currentSpace =
        (display["Current Space"] as? [String: Any])?["id64"] as? Int ?? activeSpace

      for space in spaces {
        guard let spaceID = space["id64"] as? Int else {
          continue
        }

        // Only desktops (type 0) are shown. Fullscreen apps (type 4) and
        // system spaces aren't, but still take an index.
        let spaceType = space["type"] as? Int ?? 0
        if spaceType != 0 {
          globalIndex += 1
          continue
        }

        result.append(
          Workspace(
            index: globalIndex, label: String(globalIndex + 1), isActive: spaceID == currentSpace))
        globalIndex += 1
      }
    }

    return result
  }
}

/// Calls back when the spaces there are change: one added, removed or
/// moved.
private final class SpaceListWatch: @unchecked Sendable {
  private let queue = DispatchQueue(label: "kantan.native-spaces", qos: .utility)
  private var timer: DispatchSourceTimer?
  private var known: [[Int]]?

  func start(every interval: Int, onChange: @escaping @Sendable () -> Void) {
    queue.async {
      guard self.timer == nil else { return }
      self.known = Self.current()
      let timer = DispatchSource.makeTimerSource(queue: self.queue)
      timer.schedule(
        deadline: .now() + .seconds(interval), repeating: .seconds(interval),
        leeway: .milliseconds(500))
      timer.setEventHandler { [weak self] in
        guard let self else { return }
        let now = Self.current()
        guard now != self.known else { return }
        self.known = now
        onChange()
      }
      self.timer = timer
      timer.resume()
    }
  }

  func stop() {
    queue.async {
      self.timer?.cancel()
      self.timer = nil
    }
  }

  private static func current() -> [[Int]]? {
    (CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: Any]])
      .map(NativeWorkspaces.spaceIDs(of:))
  }
}
