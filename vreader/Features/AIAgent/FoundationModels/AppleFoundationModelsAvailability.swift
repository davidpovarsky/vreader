// Purpose: Runtime availability checking and status mapping for Apple Foundation Models on iOS 27.
// Maps system states into deterministic domain states testable in CI.

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

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
    private let isTestOverride: Bool

    init(state: AppleFoundationModelsAvailabilityState) {
        self.state = state
        self.isTestOverride = true
    }

    init(simulatedState: AppleFoundationModelsAvailabilityState? = nil) {
        self.state = simulatedState ?? .deviceNotSupported
        self.isTestOverride = simulatedState != nil
    }

    init() {
        self.state = .deviceNotSupported
        self.isTestOverride = false
    }

    var isAvailable: Bool {
        checkAvailability().isAvailable
    }

    var statusDescription: String {
        checkAvailability().displayDescription
    }

    /// Evaluates runtime availability of Apple Foundation Models using system APIs on iOS 26+.
    func checkAvailability() -> AppleFoundationModelsAvailabilityState {
        if isTestOverride {
            return state
        }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return .deviceNotSupported
                case .appleIntelligenceNotEnabled:
                    return .disabledInSystemSettings
                case .modelNotReady:
                    return .modelNotDownloaded
                default:
                    return .restricted
                }
            @unknown default:
                return .unknown
            }
        } else {
            return .deviceNotSupported
        }
        #else
        return state
        #endif
    }
}
