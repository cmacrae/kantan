import AppKit

class EventObserver {
    let workspace = NSWorkspace.shared

    init() {
        let notificationCenter = workspace.notificationCenter
        notificationCenter.addObserver(self, selector: #selector(activeSpaceDidChange(_:)), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        notificationCenter.addObserver(self, selector: #selector(appSwitched(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)

        notificationCenter.addObserver(self, selector: #selector(willSleep(_:)), name: NSWorkspace.willSleepNotification, object: nil)

        notificationCenter.addObserver(self, selector: #selector(didWake(_:)), name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc func activeSpaceDidChange(_ notification: Notification) {
        // Handle event
    }

    @objc func appSwitched(_ notification: Notification) {
        // Handle event
    }

    @objc func willSleep(_ notification: Notification) {
        // Handle event
    }

    @objc func didWake(_ notification: Notification) {
        // Handle event
    }
}
