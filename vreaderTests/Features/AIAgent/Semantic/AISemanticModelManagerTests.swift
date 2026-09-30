// Purpose: Unit tests for AISemanticModelManager download lifecycle and state transitions.
// Verifies explicit user trigger requirement, progress reporting, removal, and no auto-download on launch.

import Testing
import Foundation
@testable import vreader

@Suite("AISemanticModelManagerTests")
struct AISemanticModelManagerTests {

    @Test func managerInitializesInNotInstalledOrExistingStateWithoutDownloading() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let manager = AISemanticModelManager(storageDirectory: tempDir)

        // Must NOT start downloading automatically
        #expect(manager.state == .notInstalled || manager.state == .installed)
        #expect(manager.isModelReady == false)
    }

    @Test func removeModelCleansDirectoryAndResetsState() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fakeModelFile = tempDir.appendingPathComponent("model.bin")
        try Data([0x01, 0x02, 0x03]).write(to: fakeModelFile)

        let manager = AISemanticModelManager(storageDirectory: tempDir)
        try await manager.removeModel()

        #expect(manager.state == .notInstalled)
        #expect(manager.diskUsageBytes() == 0)
    }

    @Test func stateDescriptionsAndTitles() {
        #expect(AISemanticModelState.notInstalled.displayTitle == "Not Installed")
        #expect(AISemanticModelState.downloading(progress: 0.5).displayTitle.contains("50%"))
        #expect(AISemanticModelState.ready.displayTitle == "Ready")
        #expect(AISemanticModelState.failed("Network error").displayTitle == "Download Failed")
    }
}
