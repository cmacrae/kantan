import Foundation
import IOKit.pwr_mgt
import Yaml

struct CaffeinateConfigFactory: ModuleConfigurationFactory {
    func configuration(from yaml: Yaml) throws -> ModuleConfiguration {
        return CaffeinateConfig()
    }

    func defaultConfiguration() -> ModuleConfiguration? {
        return CaffeinateConfig()
    }
}

struct CaffeinateConfig: ModuleConfiguration {
    var type: String { "caffeinate" }
    var redrawInterval: TimeInterval { 3600.0 }

    private let state = CaffeinateState()

    func getValue(completion: @escaping @Sendable (String) -> Void) {
        completion("")
    }

    func getIcon() -> String { "" }

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
    private(set) var isActive: Bool = false
    private var assertionID: IOPMAssertionID = 0

    func toggle() {
        if isActive { deactivate() } else { activate() }
    }

    private func activate() {
        guard !isActive else { return }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Kantan Caffeinate" as CFString,
            &assertionID
        )
        if result == kIOReturnSuccess {
            isActive = true
        }
    }

    private func deactivate() {
        guard isActive else { return }
        let result = IOPMAssertionRelease(assertionID)
        if result == kIOReturnSuccess {
            isActive = false
            assertionID = 0
        }
    }

    deinit {
        if isActive {
            IOPMAssertionRelease(assertionID)
        }
    }
}
