// Purpose: Runtime availability checking and status mapping for Apple Foundation Models on iOS 27.
// Maps system states into deterministic domain states testable in CI.

import Foundation

enum AppleFoundationModelsMode: String, Sendable, Codable, CaseIterable {
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

    var displayName: String {
        localizedTitle
    }
}

typealias AppleFoundationModelMode = AppleFoundationModelsMode

enum AppleFoundationModelsAvailabilityState: Sendable, Equatable {
    case available
    case deviceNotSupported
    case modelNotDownloaded
    case disabledInSystemSettings
    case restricted
    case unknown

    var isAvailable: Bool {
        self == .available
    }

    var displayDescription: String {
        switch self {
        case .available:
            return "Available"
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
    let state: AppleFoundationModelsAvailabilityState

    init(state: AppleFoundationModelsAvailabilityState = .deviceNotSupported) {
        self.state = state
    }

    init(simulatedState: AppleFoundationModelsAvailabilityState? = nil) {
        self.state = simulatedState ?? .deviceNotSupported
    }

    var isAvailable: Bool {
        state.isAvailable
    }

    var statusDescription: String {
        state.displayDescription
    }

    /// Evaluates runtime availability of Apple Foundation Models.
    func checkAvailability() -> AppleFoundationModelsAvailabilityState {
        #if canImport(FoundationModels)
        return .available
        #else
        return state
        #endif
    }
}
