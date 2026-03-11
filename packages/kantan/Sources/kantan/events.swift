import AppKit

final class EventObserver {
  private let workspace = NSWorkspace.shared
  private let onRefresh: @MainActor () -> Void
  private let onSleep: @MainActor () -> Void
  private let onWake: @MainActor () -> Void
  private let onEvent: @MainActor (String, String, [String: String]) -> Void

  init(
    onRefresh: @escaping @MainActor () -> Void,
    onSleep: @escaping @MainActor () -> Void,
    onWake: @escaping @MainActor () -> Void,
    onEvent: @escaping @MainActor (String, String, [String: String]) -> Void
  ) {
    self.onRefresh = onRefresh
    self.onSleep = onSleep
    self.onWake = onWake
    self.onEvent = onEvent
    let notificationCenter = workspace.notificationCenter

    notificationCenter.addObserver(
      self, selector: #selector(activeSpaceDidChange(_:)),
      name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

    notificationCenter.addObserver(
      self, selector: #selector(willSleep(_:)), name: NSWorkspace.willSleepNotification, object: nil
    )

    notificationCenter.addObserver(
      self, selector: #selector(didWake(_:)), name: NSWorkspace.didWakeNotification, object: nil)

    DistributedNotificationCenter.default().addObserver(
      self,
      selector: #selector(kantanEvent(_:)),
      name: NSNotification.Name("com.kantan.event"),
      object: nil
    )
  }

  deinit {
    workspace.notificationCenter.removeObserver(self)
    DistributedNotificationCenter.default().removeObserver(self)
  }

  private func dispatchToMain(_ callback: @escaping @MainActor () -> Void) {
    Task { @MainActor in
      callback()
    }
  }

  @objc private func activeSpaceDidChange(_ notification: Notification) {
    dispatchToMain(onRefresh)
  }

  @objc private func willSleep(_ notification: Notification) {
    dispatchToMain(onSleep)
  }

  @objc private func didWake(_ notification: Notification) {
    dispatchToMain(onWake)
  }

  @objc private func kantanEvent(_ notification: Notification) {
    guard let userInfo = notification.userInfo as? [String: String],
      let module = userInfo["module"],
      let action = userInfo["action"]
    else {
      return
    }
    dispatchToMain { [onEvent] in onEvent(module, action, userInfo) }
  }
}
