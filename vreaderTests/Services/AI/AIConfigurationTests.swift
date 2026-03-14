// Purpose: Tests for AIConfiguration and AIConfigurationStore.
// Verifies default values and persistence to PreferenceStoring.

import Testing
import Foundation
@testable import vreader

@Suite("AIConfiguration")
struct AIConfigurationTests {

    // MARK: - Default Configuration

    @Test func defaultConfiguration() {
        let config = AIConfiguration.default
        #expect(config.model == "gpt-4o-mini")
        #expect(config.temperature == 0.7)
        #expect(config.maxTokens == 2048)
        #expect(config.endpoint == URL(string: "https://api.openai.com/v1")!)
    }

    @Test func customConfiguration() {
        let url = URL(string: "http://localhost:11434/v1")!
        let config = AIConfiguration(
            model: "llama3",
            temperature: 0.5,
            endpoint: url,
            maxTokens: 4096
        )
        #expect(config.model == "llama3")
        #expect(config.temperature == 0.5)
        #expect(config.endpoint == url)
        #expect(config.maxTokens == 4096)
    }

    // MARK: - Store Persistence

    @Test func configurationPersists() {
        let store = MockPreferenceStore()
        let configStore = AIConfigurationStore(preferences: store)

        let custom = AIConfiguration(
            model: "gpt-4o",
            temperature: 0.3,
            endpoint: URL(string: "https://custom.api.com/v1")!,
            maxTokens: 4096
        )
        configStore.save(custom)

        let loaded = configStore.load()
        #expect(loaded.model == "gpt-4o")
        #expect(loaded.temperature == 0.3)
        #expect(loaded.endpoint == URL(string: "https://custom.api.com/v1")!)
        #expect(loaded.maxTokens == 4096)
    }

    @Test func loadReturnsDefaultWhenEmpty() {
        let store = MockPreferenceStore()
        let configStore = AIConfigurationStore(preferences: store)

        let loaded = configStore.load()
        #expect(loaded.model == AIConfiguration.default.model)
        #expect(loaded.temperature == AIConfiguration.default.temperature)
        #expect(loaded.endpoint == AIConfiguration.default.endpoint)
        #expect(loaded.maxTokens == AIConfiguration.default.maxTokens)
    }

    @Test func loadReturnsDefaultOnCorruptedData() {
        let store = MockPreferenceStore()
        store.setRaw("not valid json", forKey: "com.vreader.ai.configuration")
        let configStore = AIConfigurationStore(preferences: store)

        let loaded = configStore.load()
        #expect(loaded.model == AIConfiguration.default.model)
    }

    @Test func partialConfigurationUsesDefaults() {
        let store = MockPreferenceStore()
        // Store only model, leave others at default
        let configStore = AIConfigurationStore(preferences: store)
        let partial = AIConfiguration(
            model: "claude-3",
            temperature: AIConfiguration.default.temperature,
            endpoint: AIConfiguration.default.endpoint,
            maxTokens: AIConfiguration.default.maxTokens
        )
        configStore.save(partial)

        let loaded = configStore.load()
        #expect(loaded.model == "claude-3")
        #expect(loaded.temperature == AIConfiguration.default.temperature)
    }
}
