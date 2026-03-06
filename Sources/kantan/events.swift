import AppKit

class EventObserver {
    let workspace = NSWorkspace.shared
    private let onRefresh: @MainActor () -> Void

    init(onRefresh: @escaping @MainActor () -> Void) {
        self.onRefresh = onRefresh
        let notificationCenter = workspace.notificationCenter

        notificationCenter.addObserver(self, selector: #selector(activeSpaceDidChange(_:)), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        notificationCenter.addObserver(self, selector: #selector(appSwitched(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)

        notificationCenter.addObserver(self, selector: #selector(willSleep(_:)), name: NSWorkspace.willSleepNotification, object: nil)

        notificationCenter.addObserver(self, selector: #selector(didWake(_:)), name: NSWorkspace.didWakeNotification, object: nil)
    }

    deinit {
        workspace.notificationCenter.removeObserver(self)
    }

    @objc func activeSpaceDidChange(_ notification: Notification) {
        triggerRefresh()
    }

    @objc func appSwitched(_ notification: Notification) {
    }

    @objc func willSleep(_ notification: Notification) {
    }

    @objc func didWake(_ notification: Notification) {
        triggerRefresh()
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
