// Purpose: Policy enforcement and privacy/consent routing for Apple Foundation Models execution.
// Strictly prevents on-device mode from leaking data to cloud/PCC.

import Foundation

struct AppleFoundationModelsPolicy: Sendable {
    let mode: AppleFoundationModelMode
    let isPCCConsentGranted: Bool

    init(
        mode: AppleFoundationModelMode = .onDevice,
        isPCCConsentGranted: Bool = false
    ) {
        self.mode = mode
        self.isPCCConsentGranted = isPCCConsentGranted
    }

    /// Resolves the actual execution path, enforcing privacy invariants.
    func resolveExecutionMode(availableModes: [AppleFoundationModelMode]) -> AppleFoundationModelMode? {
        switch mode {
        case .onDevice:
            // STRICT: Must use on-device only. Never fall back to PCC or cloud.
            return availableModes.contains(.onDevice) ? .onDevice : nil

        case .privateCloudCompute:
            // Requires both runtime availability and explicit PCC consent
            guard isPCCConsentGranted, availableModes.contains(.privateCloudCompute) else {
                return nil
            }
            return .privateCloudCompute

        case .automatic:
            if availableModes.contains(.onDevice) {
                return .onDevice
            }
            if isPCCConsentGranted && availableModes.contains(.privateCloudCompute) {
                return .privateCloudCompute
            }
            return nil
        }
    }

    /// Whether data leaves the local device for this configuration.
    var transmitsDataOffDevice: Bool {
        switch mode {
        case .onDevice: return false
        case .privateCloudCompute: return true
        case .automatic: return isPCCConsentGranted
        }
    }
}
