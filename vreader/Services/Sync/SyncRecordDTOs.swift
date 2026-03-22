// Purpose: Lightweight DTOs for CloudKit record mapping.
// Used by CloudKitRecordMapper for bidirectional CKRecord conversion.
// Separate from SyncConflictResolver's record types (which model conflict fields only).
//
// Key decisions:
// - All types Sendable for cross-actor safety.
// - CK* prefix on types that would collide with SyncConflictResolver records.
// - Boolean fields stored as Bool here; CloudKitRecordMapper handles Int64 encoding.
// - Locator stored as JSON string for forward compatibility (D3).
// - Data blobs for rule fields (BookSource) stored as optional Data.
//
// @coordinates-with: CloudKitRecordMapper.swift

import Foundation

// MARK: - Book

/// Lightweight DTO for VRBook CKRecord mapping.
struct SyncBookRecord: Sendable, Equatable {
    let fingerprintKey: String
    let title: String
    let author: String?
    let format: String
    let fileByteCount: Int64
    let addedAt: Date
    let tags: [String]
    let isFavorite: Bool
    let detectedEncoding: String?
    let updatedAt: Date
}

// MARK: - Reading Position

/// Lightweight DTO for VRReadingPosition CKRecord mapping.
struct SyncReadingPositionRecord: Sendable, Equatable {
    let bookFingerprintKey: String
    let locatorJSON: String
    let updatedAt: Date
    let deviceId: String
}

// MARK: - Bookmark

/// Lightweight DTO for VRBookmark CKRecord mapping.
/// Named SyncCKBookmarkRecord to avoid collision with SyncBookmarkRecord in SyncConflictResolver.
struct SyncCKBookmarkRecord: Sendable, Equatable {
    let bookmarkId: String
    let bookFingerprintKey: String
    let locatorJSON: String
    let title: String?
    let createdAt: Date
    let updatedAt: Date
    let isDeleted: Bool
}

// MARK: - Highlight

/// Lightweight DTO for VRHighlight CKRecord mapping.
/// Named SyncCKHighlightRecord to avoid collision with SyncHighlightRecord in SyncConflictResolver.
struct SyncCKHighlightRecord: Sendable, Equatable {
    let highlightId: String
    let bookFingerprintKey: String
    let locatorJSON: String
    let selectedText: String
    let color: String
    let note: String?
    let createdAt: Date
    let updatedAt: Date
    let isDeleted: Bool
}

// MARK: - Annotation

/// Lightweight DTO for VRAnnotation CKRecord mapping.
/// Named SyncCKAnnotationRecord to avoid collision with SyncAnnotationRecord in SyncConflictResolver.
struct SyncCKAnnotationRecord: Sendable, Equatable {
    let annotationId: String
    let bookFingerprintKey: String
    let locatorJSON: String
    let content: String
    let createdAt: Date
    let updatedAt: Date
    let isDeleted: Bool
}

// MARK: - Reading Session

/// Lightweight DTO for VRReadingSession CKRecord mapping.
struct SyncReadingSessionRecord: Sendable, Equatable {
    let sessionId: String
    let bookFingerprintKey: String
    let startedAt: Date
    let endedAt: Date?
    let durationSeconds: Int
    let pagesRead: Int?
    let wordsRead: Int?
    let deviceId: String
    let isRecovered: Bool
}

// MARK: - Book Source

/// Lightweight DTO for VRBookSource CKRecord mapping.
struct SyncBookSourceRecord: Sendable, Equatable {
    let sourceURL: String
    let sourceName: String
    let sourceGroup: String?
    let sourceType: String
    let enabled: Bool
    let searchURL: String?
    let ruleSearchData: Data?
    let ruleBookInfoData: Data?
    let ruleTocData: Data?
    let ruleContentData: Data?
    let updatedAt: Date
    let isDeleted: Bool
}

// MARK: - Replacement Rule

/// Lightweight DTO for VRReplacementRule CKRecord mapping.
struct SyncReplacementRuleRecord: Sendable, Equatable {
    let ruleId: String
    let pattern: String
    let replacement: String
    let isRegex: Bool
    let scopeKey: String?
    let enabled: Bool
    let order: Int
    let label: String?
    let createdAt: Date
    let isDeleted: Bool
}
