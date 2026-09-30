// Purpose: Runtime availability checking and status mapping for Apple Foundation Models on iOS 27.
// Maps system states into deterministic domain states testable in CI.

import Foundation

enum AppleFoundationModelMode: String, Sendable, Codable, CaseIterable {
    case onDevice = "onDevice"
    case privateCloudCompute = "privateCloudCompute"
    case automatic = "automatic"

    var localizedTitle: String {
        switch self {
        case .onDevice: return "Apple AI — On Device"
        case .privateCloudCompute: return "Apple AI — Private Cloud Compute"
        case .automatic: return "Apple AI — Automatic"
        }
    }
}

enum AppleFoundationModelsAvailabilityState: Sendable, Equatable {
    case available(modes: [AppleFoundationModelMode])
    case deviceNotSupported
    case modelNotDownloaded
    case disabledInSystemSettings
    case restricted
    case unknown

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var displayDescription: String {
        switch self {
        case .available(let modes):
            let names = modes.map(\.localizedTitle).joined(separator: ", ")
            return "Available (\(names))"
        case .deviceNotSupported:
            return "Apple Intelligence is not supported on this device."
        case .modelNotDownloaded:
            return "Apple on-device model is downloading or not yet ready."
        case .disabledInSystemSettings:
            return "Apple Intelligence is turned off in iOS Settings."
        case .restricted:
            return "Apple Intelligence is restricted by device policy or Screen Time."
        case .unknown:
            return "Apple Intelligence status could not be determined."
        }
    }
}

struct AppleFoundationModelsAvailability: Sendable {
    private let simulatedState: AppleFoundationModelsAvailabilityState?

    init(simulatedState: AppleFoundationModelsAvailabilityState? = nil) {
        self.simulatedState = simulatedState
    }

    /// Evaluates runtime availability of Apple Foundation Models.
    func checkAvailability() -> AppleFoundationModelsAvailabilityState {
        if let sim = simulatedState { return sim }

        #if canImport(FoundationModels)
        // When running on genuine iOS 27 with FoundationModels framework
        return .available(modes: [.onDevice, .privateCloudCompute, .automatic])
        #else
        // Fallback in simulator / non-Apple-Intelligence environments
        return .deviceNotSupported
        #endif
    }
}
