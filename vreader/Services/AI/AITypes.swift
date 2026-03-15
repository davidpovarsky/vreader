// Purpose: Data models for AI assistant requests, responses, and streaming chunks.
// Defines the action taxonomy, request/response DTOs, and cache key generation.
//
// Key decisions:
// - All types are Sendable for Swift 6 strict concurrency.
// - AIActionType is Codable for cache serialization.
// - Cache key is deterministic from (fingerprint, locatorHash, actionType,
//   promptVersion, userPrompt, targetLanguage, contextText).
// - bookFingerprint and locator are optional to support general chat (no book context).
// - AIRequest is not Codable — it carries runtime context that should not be serialized directly.
// - AIResponse is Codable for cache storage.
//
// @coordinates-with: AIService.swift, AIResponseCache.swift

import Foundation
import CryptoKit

/// Categories of AI actions available to the reader.
enum AIActionType: String, Codable, Sendable, CaseIterable {
    case summarize
    case explain
    case translate
    case vocabulary
    case questionAnswer
}

/// A request to the AI provider with full context.
struct AIRequest: Sendable {
    let actionType: AIActionType
    let bookFingerprint: DocumentFingerprint?
    let locator: Locator?
    let contextText: String
    let userPrompt: String?
    let targetLanguage: String?
    let promptVersion: String

    /// Deterministic cache key for deduplication.
    /// Format: "{fpKey}:{locHash}:{action}:{promptHash}:{langHash}:{ctxHash}"
    /// Uses "general" prefix and "none" locator hash when book context is absent.
    var cacheKey: String {
        let fpKey = bookFingerprint?.canonicalKey ?? "general"
        let locHash = locator?.canonicalHash ?? "none"
        let promptHash = stableHash(userPrompt)
        let langHash = stableHash(targetLanguage)
        let ctxHash = stableHash(contextText)
        return "\(fpKey):\(locHash):\(actionType.rawValue):\(promptVersion):\(promptHash):\(langHash):\(ctxHash)"
    }

    /// Produces a short stable hash for a string, or "nil" for nil input.
    private func stableHash(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "nil" }
        let digest = SHA256.hash(data: Data(value.utf8))
        // Use first 8 bytes (16 hex chars) for brevity
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

/// A completed AI response, suitable for caching.
struct AIResponse: Codable, Sendable, Equatable {
    let content: String
    let actionType: AIActionType
    let promptVersion: String
    let createdAt: Date
}

/// A chunk from a streaming AI response.
struct AIStreamChunk: Sendable, Equatable {
    let text: String
    let isComplete: Bool
}
