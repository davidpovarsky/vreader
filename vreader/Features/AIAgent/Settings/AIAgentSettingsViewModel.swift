// Purpose: ViewModel driving the advanced AI settings, permissions, semantic model, and MCP screens.

#if canImport(UIKit)
import SwiftUI

@Observable
final class AIAgentSettingsViewModel: @unchecked Sendable {
    var preferences: AIAgentPreferences = .default
    var capabilities: AIAgentCapabilityPreferences = .default
    var modelState: AISemanticModelState = .notInstalled
    var modelDiskUsage: Int64 = 0
    var mcpProfiles: [MCPServerProfile] = []
    var isAgenticToolsEnabled: Bool = false
    var libraryIndexerState: AIAgentSemanticLibraryIndexerState = .idle

    var isLibraryIndexing: Bool {
        libraryIndexerState.isIndexing
    }

    var libraryIndexStatusText: String {
        libraryIndexerState.displayDescription
    }

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
        if let mem = preferencesStore as? InMemoryAIAgentPreferencesStore {
            self.preferences = mem.preferences
        } else {
            self.preferences = .default
        }
        self.capabilities = .default
        self.modelState = .notInstalled
        self.modelDiskUsage = 0
        self.mcpProfiles = []
        self.isAgenticToolsEnabled = false
    }

    func load() async {
        preferences = await preferencesStore.load()
        capabilities = await capabilityStore.load()
        modelState = await modelManager.state
        modelDiskUsage = await modelManager.diskUsageBytes()
        mcpProfiles = await mcpProfileStore.allProfiles()
        isAgenticToolsEnabled = FeatureFlags.shared.isEnabled(.agenticTools)
        libraryIndexerState = await AIAgentProductionRuntime.shared.libraryIndexer?.state ?? .idle
    }

    var readAheadMode: AIReadAheadMode {
        get { preferences.readAheadMode }
        set { setReadAheadMode(newValue) }
    }

    func permission(for category: AIToolPermissionCategory) -> AIToolPermissionDecision {
        preferences.decision(for: category)
    }

    func setPermission(_ category: AIToolPermissionCategory, policy: AIToolPermissionDecision) {
        // Enforce that removeData is always ask
        if category == .removeData { return }
        preferences.setDecision(policy, for: category)
        if let mem = preferencesStore as? InMemoryAIAgentPreferencesStore {
            mem.preferences.setDecision(policy, for: category)
        }
        Task {
            await preferencesStore.setDecision(policy, for: category)
        }
    }

    func setDecision(_ decision: AIToolPermissionDecision, for category: AIToolPermissionCategory) async {
        setPermission(category, policy: decision)
    }

    func setReadAheadMode(_ mode: AIReadAheadMode) {
        preferences.setReadAheadMode(mode)
        if let mem = preferencesStore as? InMemoryAIAgentPreferencesStore {
            mem.preferences.setReadAheadMode(mode)
        }
        Task {
            await preferencesStore.setReadAheadMode(mode)
        }
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

    func setBackendChoice(_ choice: AIAgentBackendChoice) async {
        capabilities.backendChoice = choice
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

    func rebuildLibraryIndex() async {
        try? await AIAgentProductionRuntime.shared.libraryIndexer?.rebuildLibraryIndex()
        libraryIndexerState = await AIAgentProductionRuntime.shared.libraryIndexer?.state ?? .idle
    }

    func cancelLibraryIndexing() async {
        await AIAgentProductionRuntime.shared.libraryIndexer?.cancelIndexing()
        libraryIndexerState = await AIAgentProductionRuntime.shared.libraryIndexer?.state ?? .idle
    }

    // MARK: - MCP Actions

    func toggleMCPProfile(_ profile: MCPServerProfile) async {
        var updated = profile
        updated.isEnabled.toggle()
        try? await mcpProfileStore.saveProfile(updated)
        mcpProfiles = await mcpProfileStore.allProfiles()
    }

    func deleteMCPProfile(_ profile: MCPServerProfile) async {
        await mcpProfileStore.removeProfile(withID: profile.id)
        mcpProfiles = await mcpProfileStore.allProfiles()
    }
}
#endif
