// Purpose: Unit tests for AppleFoundationModelsPolicy.
// Validates privacy guarantees: onDevice mode never uses network, PCC requires consent, and automatic falls back safely.

import Testing
import Foundation
@testable import vreader

@Suite("AppleFoundationModelsPolicyTests")
struct AppleFoundationModelsPolicyTests {

    @Test func onDeviceModeNeverPermitsNetworkOrPCC() {
        let policy = AppleFoundationModelsPolicy(mode: .onDevice, userConsentedToPCC: true)
        #expect(policy.permitsNetworkAccess == false)
        #expect(policy.permitsPrivateCloudCompute == false)
    }

    @Test func pccModeRequiresExplicitUserConsent() {
        let policyNoConsent = AppleFoundationModelsPolicy(mode: .privateCloudCompute, userConsentedToPCC: false)
        #expect(policyNoConsent.canExecute == false)

        let policyWithConsent = AppleFoundationModelsPolicy(mode: .privateCloudCompute, userConsentedToPCC: true)
        #expect(policyWithConsent.canExecute == true)
        #expect(policyWithConsent.permitsPrivateCloudCompute == true)
    }

    @Test func automaticModePrefersOnDeviceWhenAvailable() {
        let policy = AppleFoundationModelsPolicy(mode: .automatic, userConsentedToPCC: false)
        let resolved = policy.resolveExecutionMode(onDeviceAvailable: true, pccAvailable: true)
        #expect(resolved == .onDevice)
    }

    @Test func automaticModeFallsToPCCWhenOnDeviceUnavailableAndConsented() {
        let policy = AppleFoundationModelsPolicy(mode: .automatic, userConsentedToPCC: true)
        let resolved = policy.resolveExecutionMode(onDeviceAvailable: false, pccAvailable: true)
        #expect(resolved == .privateCloudCompute)
    }

    @Test func automaticModeReturnsNilWhenNoPermittedEngineIsAvailable() {
        let policy = AppleFoundationModelsPolicy(mode: .automatic, userConsentedToPCC: false)
        let resolved = policy.resolveExecutionMode(onDeviceAvailable: false, pccAvailable: true)
        #expect(resolved == nil)
    }
}
