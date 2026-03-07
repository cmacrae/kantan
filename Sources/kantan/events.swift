import AppKit

class EventObserver {
    let workspace = NSWorkspace.shared
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

        notificationCenter.addObserver(self, selector: #selector(activeSpaceDidChange(_:)), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        notificationCenter.addObserver(self, selector: #selector(appSwitched(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)

        notificationCenter.addObserver(self, selector: #selector(willSleep(_:)), name: NSWorkspace.willSleepNotification, object: nil)

        notificationCenter.addObserver(self, selector: #selector(didWake(_:)), name: NSWorkspace.didWakeNotification, object: nil)

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

    @objc func activeSpaceDidChange(_ notification: Notification) {
        triggerRefresh()
    }

    @objc func appSwitched(_ notification: Notification) {
    }

    @objc func willSleep(_ notification: Notification) {
        let callback = onSleep
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                callback()
            }
        }
    }

    @objc func didWake(_ notification: Notification) {
        let callback = onWake
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                callback()
            }
        }
    }

    @objc func kantanEvent(_ notification: Notification) {
        guard let userInfo = notification.userInfo as? [String: String],
              let module = userInfo["module"],
              let action = userInfo["action"] else {
            return
        }
        let callback = onEvent
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                callback(module, action, userInfo)
            }
        }
    }

    private func triggerRefresh() {
        let callback = onRefresh
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                callback()
            }
        }
    }
}
