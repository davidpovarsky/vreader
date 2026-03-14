// Purpose: Configuration for AI provider (model, temperature, endpoint, maxTokens).
// Separated from provider creation to allow persistence and UI configuration.
//
// Key decisions:
// - Codable for JSON persistence via AIConfigurationStore.
// - Sendable for cross-actor use.
// - Static `.default` provides sensible defaults for OpenAI.
// - Endpoint is a URL validated at construction; Codable uses string representation.
//
// @coordinates-with: AIConfigurationStore.swift, AIService.swift, AIProvider.swift

import Foundation

/// Configuration for an AI provider.
struct AIConfiguration: Codable, Sendable, Equatable {
    /// The model identifier (e.g., "gpt-4o-mini", "llama3").
    let model: String

    /// Sampling temperature (0.0 = deterministic, 1.0 = creative).
    let temperature: Double

    /// The provider API endpoint base URL.
    let endpoint: URL

    /// Maximum tokens in the response.
    let maxTokens: Int

    /// Sensible defaults for OpenAI.
    static let `default` = AIConfiguration(
        model: "gpt-4o-mini",
        temperature: 0.7,
        // swiftlint:disable:next force_unwrapping
        endpoint: URL(string: "https://api.openai.com/v1")!,
        maxTokens: 2048
    )
}
