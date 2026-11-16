import Foundation

/// Native macOS spaces across all displays, refreshed by EventObserver on
/// NSWorkspace.activeSpaceDidChangeNotification.
struct NativeWorkspaces: WorkspaceProvider {
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
