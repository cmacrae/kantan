import Foundation
import IOKit.pwr_mgt
import Yaml

struct CaffeinateConfigFactory: ModuleConfigurationFactory {
    func configuration(from yaml: Yaml, configDir: String?) throws -> ModuleConfiguration {
        return CaffeinateConfig()
    }

    func defaultConfiguration() -> ModuleConfiguration? {
        return CaffeinateConfig()
    }
}

struct CaffeinateConfig: ModuleConfiguration {
    var type: String { "caffeinate" }
    var redrawInterval: TimeInterval { noPoll }

    private let state = CaffeinateState()

    func getValue(completion: @escaping @Sendable (String) -> Void) {
        completion("")
    }

    func isActive() -> Bool {
        state.isActive
    }

    func getTemplateVariables() -> [String: String] {
        ["status": state.isActive ? "on" : "off"]
    }

    func handleToggle() {
        state.toggle()
    }

    init() {}

    init(from decoder: Decoder) throws {}
    func encode(to encoder: Encoder) throws {}
}

final class CaffeinateState: @unchecked Sendable {
    private let lock = NSLock()
    private var _isActive: Bool = false
    private var assertionID: IOPMAssertionID = 0

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isActive
    }

    func toggle() {
        lock.lock()
        defer { lock.unlock() }
        if _isActive { _deactivate() } else { _activate() }
    }

    private func _activate() {
        guard !_isActive else { return }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Kantan Caffeinate" as CFString,
            &assertionID
        )
        if result == kIOReturnSuccess {
            _isActive = true
        }
    }

    private func _deactivate() {
        guard _isActive else { return }
        let result = IOPMAssertionRelease(assertionID)
        if result == kIOReturnSuccess {
            _isActive = false
            assertionID = 0
        }
    }

    deinit {
        if _isActive {
            IOPMAssertionRelease(assertionID)
        }
    }
}
