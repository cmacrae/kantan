import Foundation
import Yaml

// MARK: - Workspace Segment Data

struct WorkspaceSegment: Sendable {
  let label: String
  let isActive: Bool
  /// When the label came from a named icon (e.g. "point-filled"),
  /// this holds the font family name to render it with.
  let fontNameOverride: String?
  /// Dynamic scale factor for the icon glyph (1.0 = no adjustment).
  let scaleFactor: CGFloat

  init(label: String, isActive: Bool, fontNameOverride: String? = nil, scaleFactor: CGFloat = 1.0) {
    self.label = label
    self.isActive = isActive
    self.fontNameOverride = fontNameOverride
    self.scaleFactor = scaleFactor
  }
}

// Module-level cache for structured workspace data.
// The drawing pipeline reads this to render per-space indicators.
nonisolated(unsafe) private var cachedSegments: [WorkspaceSegment] = []
private let segmentsLock = NSLock()

func getWorkspaceSegments() -> [WorkspaceSegment] {
  segmentsLock.lock()
  defer { segmentsLock.unlock() }
  return cachedSegments
}

private func setWorkspaceSegments(_ segments: [WorkspaceSegment]) {
  segmentsLock.lock()
  defer { segmentsLock.unlock() }
  cachedSegments = segments
}

// MARK: - Factory

struct WorkspaceConfigFactory: ModuleConfigurationFactory {
  func configuration(from yaml: Yaml, configDir: String?, theme: ThemeConfig?) throws
    -> ModuleConfiguration
  {
    return WorkspaceConfig(yaml: yaml)
  }

  func defaultConfiguration() -> ModuleConfiguration? {
    return WorkspaceConfig(yaml: nil)
  }
}

// MARK: - Overflow Config

struct OverflowConfig: Sendable {
  let enabled: Bool
  let max: Int
  let showIcon: Bool
  let iconLeft: String
  let iconRight: String
  let style: StyleConfig?

  static let disabled = OverflowConfig(
    enabled: false, max: 5, showIcon: true, iconLeft: "‹", iconRight: "›", style: nil)
}

// MARK: - Configuration

/// Workspace module. Native macOS spaces are event-driven via
/// NSWorkspace.activeSpaceDidChangeNotification (handled by EventObserver
/// which calls refreshAll()). Aerospace workspaces rely on CLI triggers.
/// Neither mode requires polling.
struct WorkspaceConfig: ModuleConfiguration {
  var type: String { "workspace" }

  let providerType: String  // "native" or "aerospace"
  let icons: [String]
  let aerospacePath: String?
  let overflow: OverflowConfig
  /// Module-level icon (from top-level `icon:` key), used as fallback
  /// when `config.icons` doesn't cover a space.
  var moduleIcon: String?

  // No polling needed — native uses NSWorkspace notifications via
  // EventObserver, aerospace uses CLI triggers. Both call refreshAll()
  // which invokes update() on this module.
  var redrawInterval: TimeInterval { noPoll }

  init(yaml: Yaml?) {
    self.providerType = yaml?["type"].string ?? "native"
    self.icons = yaml?["icons"].array?.compactMap { $0.string } ?? []
    self.aerospacePath = yaml?["aerospacePath"].string

    if let ofYaml = yaml?["overflow"].dictionary {
      let enabled = ofYaml["enabled"]?.bool ?? false
      let max = ofYaml["max"]?.int ?? 5
      let style = ofYaml["style"].flatMap { parseStyleConfig(from: $0) }

      // icon: false disables indicator, icon: "str" sets both,
      // icon: {left: ..., right: ...} sets individually
      let showIcon: Bool
      let iconLeft: String
      let iconRight: String
      if let iconBool = ofYaml["icon"]?.bool, iconBool == false {
        showIcon = false
        iconLeft = ""
        iconRight = ""
      } else if let iconStr = ofYaml["icon"]?.string {
        showIcon = true
        iconLeft = iconStr
        iconRight = iconStr
      } else if let iconDict = ofYaml["icon"]?.dictionary {
        showIcon = true
        iconLeft = iconDict["left"]?.string ?? "‹"
        iconRight = iconDict["right"]?.string ?? "›"
      } else {
        showIcon = true
        iconLeft = "‹"
        iconRight = "›"
      }

      self.overflow = OverflowConfig(
        enabled: enabled, max: max, showIcon: showIcon, iconLeft: iconLeft, iconRight: iconRight,
        style: style)
    } else {
      self.overflow = .disabled
    }
  }

  init(from decoder: Decoder) throws {
    self.providerType = "native"
    self.icons = []
    self.aerospacePath = nil
    self.overflow = .disabled
  }

  func encode(to encoder: Encoder) throws {}

  func getValue(completion: @escaping @Sendable (String) -> Void) {
    let provider = self.providerType
    let iconList = self.icons
    let modIcon = self.moduleIcon
    let aeroPathOverride = self.aerospacePath

    DispatchQueue.global(qos: .userInitiated).async {
      let spaces: [(index: Int, label: String, isActive: Bool)]

      switch provider {
      case "aerospace":
        let resolvedPath = aeroPathOverride ?? Self.resolveExecutable("aerospace")
        guard let path = resolvedPath else {
          completion("")
          return
        }
        spaces = Self.fetchAerospaceSpaces(path: path)
      default:
        spaces = Self.fetchNativeSpaces()
      }

      let segments = spaces.map { space -> WorkspaceSegment in
        let rawIcon: String
        if space.index < iconList.count {
          rawIcon = iconList[space.index]
        } else if let mi = modIcon, !mi.isEmpty {
          rawIcon = mi
        } else {
          rawIcon = space.label
        }
        let resolved = resolveIconName(rawIcon)
        return WorkspaceSegment(
          label: resolved.glyph, isActive: space.isActive,
          fontNameOverride: resolved.fontNameOverride,
          scaleFactor: resolved.scaleFactor)
      }

      setWorkspaceSegments(segments)

      // Return a value string that changes when workspace state changes,
      // so the drawing pipeline detects the update and redraws.
      let value = segments.map { ($0.isActive ? ">" : "") + $0.label }
        .joined(separator: " ")
      completion(value)
    }
  }

  // MARK: - Native macOS Spaces

  private static func fetchNativeSpaces()
    -> [(index: Int, label: String, isActive: Bool)]
  {
    let cid = CGSMainConnectionID()
    let activeSpace = CGSGetActiveSpace(cid)

    guard
      let displaySpaces = CGSCopyManagedDisplaySpaces(cid)
        as? [[String: Any]]
    else {
      return []
    }

    var result: [(index: Int, label: String, isActive: Bool)] = []
    var globalIndex = 0

    for display in displaySpaces {
      guard
        let spaces = display["Spaces"] as? [[String: Any]]
      else {
        continue
      }

      for space in spaces {
        guard let spaceID = space["id64"] as? Int else {
          continue
        }

        // Skip fullscreen/system spaces (type 4 = user space)
        let spaceType = space["type"] as? Int ?? 0
        if spaceType != 0 && spaceType != 4 {
          globalIndex += 1
          continue
        }

        let isActive = spaceID == activeSpace
        let label = String(globalIndex + 1)

        result.append(
          (index: globalIndex, label: label, isActive: isActive))
        globalIndex += 1
      }
    }

    return result
  }

  // MARK: - Aerospace Spaces

  private static func fetchAerospaceSpaces(path: String)
    -> [(index: Int, label: String, isActive: Bool)]
  {
    guard
      let spacesData = runCommandSync(
        path: path, arguments: ["list-workspaces", "--all", "--json"]),
      let focusedData = runCommandSync(
        path: path, arguments: ["list-workspaces", "--focused", "--json"])
    else {
      return []
    }

    struct AeroWorkspace: Decodable {
      let workspace: String
    }

    let decoder = JSONDecoder()

    guard let allSpaces = try? decoder.decode([AeroWorkspace].self, from: spacesData),
      let focusedSpaces = try? decoder.decode([AeroWorkspace].self, from: focusedData)
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

    return sorted.enumerated().map { (index, space) in
      (
        index: index,
        label: space.workspace,
        isActive: space.workspace == focusedID
      )
    }
  }

  // MARK: - Helpers

  private static func resolveExecutable(_ name: String) -> String? {
    guard let pathVar = ProcessInfo.processInfo.environment["PATH"] else {
      return nil
    }
    let fm = FileManager.default
    for dir in pathVar.split(separator: ":") {
      let candidate = "\(dir)/\(name)"
      if fm.isExecutableFile(atPath: candidate) {
        return candidate
      }
    }
    return nil
  }
}
