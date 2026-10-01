// Purpose: Policy enforcement and privacy/consent routing for Apple Foundation Models execution.
// Strictly prevents on-device mode from leaking data to cloud/PCC.

import Foundation

struct AppleFoundationModelsPolicy: Sendable {
    let mode: AppleFoundationModelsMode
    let userConsentedToPCC: Bool

    init(
        mode: AppleFoundationModelsMode = .onDevice,
        userConsentedToPCC: Bool = false
    ) {
        self.mode = mode
        self.userConsentedToPCC = userConsentedToPCC
    }

    init(
        mode: AppleFoundationModelsMode = .onDevice,
        isPCCConsentGranted: Bool
    ) {
        self.init(mode: mode, userConsentedToPCC: isPCCConsentGranted)
    }

    var isPCCConsentGranted: Bool {
        userConsentedToPCC
    }

    var permitsNetworkAccess: Bool {
        switch mode {
        case .onDevice:
            return false
        case .privateCloudCompute, .automatic:
            return userConsentedToPCC
        }
    }

    var permitsPrivateCloudCompute: Bool {
        switch mode {
        case .onDevice:
            return false
        case .privateCloudCompute, .automatic:
            return userConsentedToPCC
        }
    }

    var canExecute: Bool {
        switch mode {
        case .onDevice:
            return true
        case .privateCloudCompute:
            return userConsentedToPCC
        case .automatic:
            return true
        }
    }

    /// Resolves the actual execution path, enforcing privacy invariants.
    func resolveExecutionMode(onDeviceAvailable: Bool, pccAvailable: Bool) -> AppleFoundationModelsMode? {
        switch mode {
        case .onDevice:
            return onDeviceAvailable ? .onDevice : nil
        case .privateCloudCompute:
            return (userConsentedToPCC && pccAvailable) ? .privateCloudCompute : nil
        case .automatic:
            if onDeviceAvailable {
                return .onDevice
            }
            if userConsentedToPCC && pccAvailable {
                return .privateCloudCompute
            }
            return nil
        }
    }

    func resolveExecutionMode(availableModes: [AppleFoundationModelsMode]) -> AppleFoundationModelsMode? {
        resolveExecutionMode(
            onDeviceAvailable: availableModes.contains(.onDevice),
            pccAvailable: availableModes.contains(.privateCloudCompute)
        )
    }

    /// Whether data leaves the local device for this configuration.
    var transmitsDataOffDevice: Bool {
        switch mode {
        case .onDevice: return false
        case .privateCloudCompute: return true
        case .automatic: return userConsentedToPCC
        }
    }
}
