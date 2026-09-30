// Purpose: Unit tests for AppleFoundationModelsAvailability.
// Tests framework availability mapping and device capability reporting without requiring live Apple Intelligence.

import Testing
import Foundation
@testable import vreader

@Suite("AppleFoundationModelsAvailabilityTests")
struct AppleFoundationModelsAvailabilityTests {

    @Test func availabilityStateMapping() {
        let available = AppleFoundationModelsAvailability(state: .available)
        #expect(available.isAvailable == true)
        #expect(available.statusDescription == "Available")

        let notSupported = AppleFoundationModelsAvailability(state: .deviceNotSupported)
        #expect(notSupported.isAvailable == false)
        #expect(notSupported.statusDescription.contains("not supported"))

        let restricted = AppleFoundationModelsAvailability(state: .restricted)
        #expect(restricted.isAvailable == false)
    }

    @Test func modeDescriptions() {
        #expect(AppleFoundationModelsMode.onDevice.displayName == "Apple AI — On Device")
        #expect(AppleFoundationModelsMode.privateCloudCompute.displayName == "Apple AI — Private Cloud Compute")
        #expect(AppleFoundationModelsMode.automatic.displayName == "Apple AI — Automatic")
    }
}
