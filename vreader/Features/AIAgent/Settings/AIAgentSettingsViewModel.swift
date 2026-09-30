// Purpose: ViewModel driving the advanced AI settings, permissions, semantic model, and MCP screens.

#if canImport(UIKit)
import SwiftUI

@Observable
@MainActor
final class AIAgentSettingsViewModel {
    var preferences: AIAgentPreferences = .default
    var capabilities: AIAgentCapabilityPreferences = .default
    var modelState: AISemanticModelState = .notInstalled
    var modelDiskUsage: Int64 = 0
    var mcpProfiles: [MCPServerProfile] = []
    var isAgenticToolsEnabled: Bool = false

    private let preferencesStore: any AIAgentPreferencesStoring
    private let capabilityStore: AIAgentCapabilityPreferencesStore
    private let modelManager: AISemanticModelManager
    private let mcpProfileStore: MCPServerProfileStore

    init(
        preferencesStore: any AIAgentPreferencesStoring = AIAgentPreferencesStore.shared,
        capabilityStore: AIAgentCapabilityPreferencesStore = .shared,
        modelManager: AISemanticModelManager = .shared,
        mcpProfileStore: MCPServerProfileStore = .shared
    ) {
        self.preferencesStore = preferencesStore
        self.capabilityStore = capabilityStore
        self.modelManager = modelManager
        self.mcpProfileStore = mcpProfileStore
    }

    func load() async {
        preferences = await preferencesStore.load()
        capabilities = await capabilityStore.load()
        modelState = await modelManager.state
        modelDiskUsage = await modelManager.diskUsageBytes()
        mcpProfiles = await mcpProfileStore.allProfiles()
        isAgenticToolsEnabled = FeatureFlags.shared.isEnabled(.agenticTools)
    }

    func setDecision(_ decision: AIToolPermissionDecision, for category: AIToolPermissionCategory) async {
        // Enforce that removeData is always ask
        if category == .removeData { return }
        await preferencesStore.setDecision(decision, for: category)
        preferences = await preferencesStore.load()
    }

    func setReadAheadMode(_ mode: AIReadAheadMode) async {
        await preferencesStore.setReadAheadMode(mode)
        preferences = await preferencesStore.load()
    }

    func setSemanticSearchEnabled(_ enabled: Bool) async {
        capabilities.isSemanticSearchEnabled = enabled
        await capabilityStore.save(capabilities)
    }

    func setOCREnabled(_ enabled: Bool) async {
        capabilities.isOCREnabled = enabled
        await capabilityStore.save(capabilities)
    }

    func setFoundationModelMode(_ mode: AppleFoundationModelMode) async {
        capabilities.foundationModelMode = mode
        await capabilityStore.save(capabilities)
    }

    func setPCCConsent(_ granted: Bool) async {
        capabilities.isPCCConsentGranted = granted
        await capabilityStore.save(capabilities)
    }

    func setAgenticToolsEnabled(_ enabled: Bool) {
        isAgenticToolsEnabled = enabled
        FeatureFlags.shared.setOverride(enabled, for: .agenticTools)
    }

    // MARK: - Semantic Model Actions

    func downloadSemanticModel() async {
        do {
            try await modelManager.downloadModel()
            modelState = await modelManager.state
            modelDiskUsage = await modelManager.diskUsageBytes()
        } catch {
            modelState = await modelManager.state
        }
    }

    func removeSemanticModel() async {
        try? await modelManager.removeModel()
        modelState = await modelManager.state
        modelDiskUsage = 0
    }

    // MARK: - MCP Actions

    func toggleMCPProfile(_ profile: MCPServerProfile) async {
        var updated = profile
        updated.isEnabled.toggle()
        await mcpProfileStore.saveProfile(updated)
        mcpProfiles = await mcpProfileStore.allProfiles()
    }

    func deleteMCPProfile(_ profile: MCPServerProfile) async {
        await mcpProfileStore.removeProfile(withID: profile.id)
        mcpProfiles = await mcpProfileStore.allProfiles()
    }
}
#endif
