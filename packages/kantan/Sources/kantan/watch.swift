import Foundation

/// Watches a directory of YAML files, and the YAML files of the directories
/// within it, for changes: a file written, replaced, added or removed.
/// While the directory is missing it is looked for again every
/// `retryInterval`, and its appearing counts as a change.
@MainActor
final class YamlTreeWatcher {
  let path: String
  private let retryInterval: TimeInterval
  private let onChange: @MainActor () -> Void
  nonisolated(unsafe) private var sources: [DispatchSourceFileSystemObject] = []
  nonisolated(unsafe) private var pending: DispatchWorkItem?

  /// How long after an event the tree is looked over again, so a file an
  /// editor replaces is back before it is watched anew.
  static let settleInterval: TimeInterval = 0.1

  init(path: String, retryInterval: TimeInterval, onChange: @escaping @MainActor () -> Void) {
    self.path = path
    self.retryInterval = retryInterval
    self.onChange = onChange
  }

  deinit {
    pending?.cancel()
    sources.forEach { $0.cancel() }
  }

  /// The directory itself, its YAML files, the directories within it and
  /// their YAML files: everything whose change is a change to the tree.
  static func watchedPaths(in path: String) -> [String] {
    let fm = FileManager.default
    func isYaml(_ name: String) -> Bool { name.hasSuffix(".yaml") || name.hasSuffix(".yml") }
    func isDirectory(_ path: String) -> Bool {
      var isDir: ObjCBool = false
      return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
    guard isDirectory(path), let entries = try? fm.contentsOfDirectory(atPath: path) else {
      return []
    }
    var paths = [path]
    for entry in entries.sorted() {
      let entryPath = (path as NSString).appendingPathComponent(entry)
      if isDirectory(entryPath) {
        paths.append(entryPath)
        let inner = (try? fm.contentsOfDirectory(atPath: entryPath)) ?? []
        paths += inner.sorted().filter(isYaml).map {
          (entryPath as NSString).appendingPathComponent($0)
        }
      } else if isYaml(entry) {
        paths.append(entryPath)
      }
    }
    return paths
  }

  func start() {
    stop()
    let paths = Self.watchedPaths(in: path)
    guard !paths.isEmpty else {
      after(retryInterval) { [weak self] in
        guard let self else { return }
        self.start()
        if !self.sources.isEmpty { self.onChange() }
      }
      return
    }

    for watched in paths {
      let fd = open(watched, O_EVTONLY)
      guard fd >= 0 else { continue }
      let source = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main)
      source.setEventHandler { [weak self] in
        MainActor.assumeIsolated { self?.changed() }
      }
      source.setCancelHandler { close(fd) }
      sources.append(source)
      source.resume()
    }
  }

  func stop() {
    pending?.cancel()
    pending = nil
    sources.forEach { $0.cancel() }
    sources.removeAll()
  }

  /// Reports the change once the tree has settled, and watches it as it
  /// then is.
  private func changed() {
    after(Self.settleInterval) { [weak self] in
      guard let self else { return }
      self.start()
      self.onChange()
    }
  }

  private func after(_ interval: TimeInterval, _ work: @escaping @MainActor () -> Void) {
    pending?.cancel()
    let item = DispatchWorkItem { MainActor.assumeIsolated { work() } }
    pending = item
    DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: item)
  }
}
