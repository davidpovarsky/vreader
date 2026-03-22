// Purpose: Bidirectional CKRecord mapping for all 8 CloudKit sync record types.
// Maps lightweight Sync* DTOs to/from CKRecord for the VReaderData custom zone.
//
// Key decisions:
// - Uses Sync* DTOs (not SwiftData @Model) for cross-boundary safety and Sendable.
// - Boolean fields stored as Int64 (0/1) in CKRecord since CloudKit has no bool type.
// - Locator stored as JSON string in CKRecord for forward compatibility (D3).
// - Tags stored as [String] (CKRecord supports string arrays natively).
// - Data blobs (rule fields) stored as NSData in CKRecord.
// - Optional fields: nil → field not set in CKRecord; missing field → nil on decode.
// - Record name = unique key per type (fingerprintKey, bookmarkId, etc.).
// - Returns nil from decode methods when required fields are missing.
//
// @coordinates-with: SyncConflictResolver.swift, SyncTypes.swift, SyncPipeline.swift

import Foundation
import CloudKit

// MARK: - Sync DTO Types

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

/// Lightweight DTO for VRReadingPosition CKRecord mapping.
struct SyncReadingPositionRecord: Sendable, Equatable {
    let bookFingerprintKey: String
    let locatorJSON: String
    let updatedAt: Date
    let deviceId: String
}

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

// MARK: - CloudKit Record Mapper

/// Bidirectional CKRecord mapping for all 8 sync record types.
enum CloudKitRecordMapper {

    // MARK: - VRBook

    static func record(from book: SyncBookRecord, zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: book.fingerprintKey, zoneID: zoneID)
        let record = CKRecord(recordType: "VRBook", recordID: recordID)
        record["title"] = book.title as NSString
        record["author"] = book.author as NSString?
        record["format"] = book.format as NSString
        record["fileByteCount"] = book.fileByteCount as NSNumber
        record["addedAt"] = book.addedAt as NSDate
        record["tags"] = book.tags as NSArray
        record["isFavorite"] = (book.isFavorite ? 1 : 0) as Int64 as NSNumber
        record["detectedEncoding"] = book.detectedEncoding as NSString?
        record["updatedAt"] = book.updatedAt as NSDate
        return record
    }

    static func book(from record: CKRecord) -> SyncBookRecord? {
        guard let title = record["title"] as? String,
              let format = record["format"] as? String,
              let addedAt = record["addedAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date else {
            return nil
        }
        let fileByteCount = (record["fileByteCount"] as? Int64) ?? 0
        let isFavorite = ((record["isFavorite"] as? Int64) ?? 0) != 0
        let tags = (record["tags"] as? [String]) ?? []
        return SyncBookRecord(
            fingerprintKey: record.recordID.recordName,
            title: title,
            author: record["author"] as? String,
            format: format,
            fileByteCount: fileByteCount,
            addedAt: addedAt,
            tags: tags,
            isFavorite: isFavorite,
            detectedEncoding: record["detectedEncoding"] as? String,
            updatedAt: updatedAt
        )
    }

    // MARK: - VRReadingPosition

    static func record(from pos: SyncReadingPositionRecord, zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: pos.bookFingerprintKey, zoneID: zoneID)
        let record = CKRecord(recordType: "VRReadingPosition", recordID: recordID)
        record["locatorJSON"] = pos.locatorJSON as NSString
        record["updatedAt"] = pos.updatedAt as NSDate
        record["deviceId"] = pos.deviceId as NSString
        return record
    }

    static func readingPosition(from record: CKRecord) -> SyncReadingPositionRecord? {
        guard let locatorJSON = record["locatorJSON"] as? String,
              let updatedAt = record["updatedAt"] as? Date,
              let deviceId = record["deviceId"] as? String else {
            return nil
        }
        return SyncReadingPositionRecord(
            bookFingerprintKey: record.recordID.recordName,
            locatorJSON: locatorJSON,
            updatedAt: updatedAt,
            deviceId: deviceId
        )
    }

    // MARK: - VRBookmark

    static func record(from bm: SyncCKBookmarkRecord, zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: bm.bookmarkId, zoneID: zoneID)
        let record = CKRecord(recordType: "VRBookmark", recordID: recordID)
        record["bookFingerprintKey"] = bm.bookFingerprintKey as NSString
        record["locatorJSON"] = bm.locatorJSON as NSString
        record["title"] = bm.title as NSString?
        record["createdAt"] = bm.createdAt as NSDate
        record["updatedAt"] = bm.updatedAt as NSDate
        record["isDeleted"] = (bm.isDeleted ? 1 : 0) as Int64 as NSNumber
        return record
    }

    static func bookmark(from record: CKRecord) -> SyncCKBookmarkRecord? {
        guard let bookFingerprintKey = record["bookFingerprintKey"] as? String,
              let locatorJSON = record["locatorJSON"] as? String,
              let createdAt = record["createdAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date else {
            return nil
        }
        let isDeleted = ((record["isDeleted"] as? Int64) ?? 0) != 0
        return SyncCKBookmarkRecord(
            bookmarkId: record.recordID.recordName,
            bookFingerprintKey: bookFingerprintKey,
            locatorJSON: locatorJSON,
            title: record["title"] as? String,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isDeleted: isDeleted
        )
    }

    // MARK: - VRHighlight

    static func record(from hl: SyncCKHighlightRecord, zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: hl.highlightId, zoneID: zoneID)
        let record = CKRecord(recordType: "VRHighlight", recordID: recordID)
        record["bookFingerprintKey"] = hl.bookFingerprintKey as NSString
        record["locatorJSON"] = hl.locatorJSON as NSString
        record["selectedText"] = hl.selectedText as NSString
        record["color"] = hl.color as NSString
        record["note"] = hl.note as NSString?
        record["createdAt"] = hl.createdAt as NSDate
        record["updatedAt"] = hl.updatedAt as NSDate
        record["isDeleted"] = (hl.isDeleted ? 1 : 0) as Int64 as NSNumber
        return record
    }

    static func highlight(from record: CKRecord) -> SyncCKHighlightRecord? {
        guard let bookFingerprintKey = record["bookFingerprintKey"] as? String,
              let locatorJSON = record["locatorJSON"] as? String,
              let selectedText = record["selectedText"] as? String,
              let color = record["color"] as? String,
              let createdAt = record["createdAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date else {
            return nil
        }
        let isDeleted = ((record["isDeleted"] as? Int64) ?? 0) != 0
        return SyncCKHighlightRecord(
            highlightId: record.recordID.recordName,
            bookFingerprintKey: bookFingerprintKey,
            locatorJSON: locatorJSON,
            selectedText: selectedText,
            color: color,
            note: record["note"] as? String,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isDeleted: isDeleted
        )
    }

    // MARK: - VRAnnotation

    static func record(from an: SyncCKAnnotationRecord, zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: an.annotationId, zoneID: zoneID)
        let record = CKRecord(recordType: "VRAnnotation", recordID: recordID)
        record["bookFingerprintKey"] = an.bookFingerprintKey as NSString
        record["locatorJSON"] = an.locatorJSON as NSString
        record["content"] = an.content as NSString
        record["createdAt"] = an.createdAt as NSDate
        record["updatedAt"] = an.updatedAt as NSDate
        record["isDeleted"] = (an.isDeleted ? 1 : 0) as Int64 as NSNumber
        return record
    }

    static func annotation(from record: CKRecord) -> SyncCKAnnotationRecord? {
        guard let bookFingerprintKey = record["bookFingerprintKey"] as? String,
              let locatorJSON = record["locatorJSON"] as? String,
              let content = record["content"] as? String,
              let createdAt = record["createdAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date else {
            return nil
        }
        let isDeleted = ((record["isDeleted"] as? Int64) ?? 0) != 0
        return SyncCKAnnotationRecord(
            annotationId: record.recordID.recordName,
            bookFingerprintKey: bookFingerprintKey,
            locatorJSON: locatorJSON,
            content: content,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isDeleted: isDeleted
        )
    }

    // MARK: - VRReadingSession

    static func record(from sess: SyncReadingSessionRecord, zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: sess.sessionId, zoneID: zoneID)
        let record = CKRecord(recordType: "VRReadingSession", recordID: recordID)
        record["bookFingerprintKey"] = sess.bookFingerprintKey as NSString
        record["startedAt"] = sess.startedAt as NSDate
        record["endedAt"] = sess.endedAt as NSDate?
        record["durationSeconds"] = Int64(sess.durationSeconds) as NSNumber
        record["pagesRead"] = sess.pagesRead.map { Int64($0) as NSNumber }
        record["wordsRead"] = sess.wordsRead.map { Int64($0) as NSNumber }
        record["deviceId"] = sess.deviceId as NSString
        record["isRecovered"] = (sess.isRecovered ? 1 : 0) as Int64 as NSNumber
        return record
    }

    static func readingSession(from record: CKRecord) -> SyncReadingSessionRecord? {
        guard let bookFingerprintKey = record["bookFingerprintKey"] as? String,
              let startedAt = record["startedAt"] as? Date,
              let deviceId = record["deviceId"] as? String else {
            return nil
        }
        let durationSeconds = (record["durationSeconds"] as? Int64).map { Int($0) } ?? 0
        let pagesRead = (record["pagesRead"] as? Int64).map { Int($0) }
        let wordsRead = (record["wordsRead"] as? Int64).map { Int($0) }
        let isRecovered = ((record["isRecovered"] as? Int64) ?? 0) != 0
        return SyncReadingSessionRecord(
            sessionId: record.recordID.recordName,
            bookFingerprintKey: bookFingerprintKey,
            startedAt: startedAt,
            endedAt: record["endedAt"] as? Date,
            durationSeconds: durationSeconds,
            pagesRead: pagesRead,
            wordsRead: wordsRead,
            deviceId: deviceId,
            isRecovered: isRecovered
        )
    }

    // MARK: - VRBookSource

    static func record(from src: SyncBookSourceRecord, zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: src.sourceURL, zoneID: zoneID)
        let record = CKRecord(recordType: "VRBookSource", recordID: recordID)
        record["sourceName"] = src.sourceName as NSString
        record["sourceGroup"] = src.sourceGroup as NSString?
        record["sourceType"] = src.sourceType as NSString
        record["enabled"] = (src.enabled ? 1 : 0) as Int64 as NSNumber
        record["searchURL"] = src.searchURL as NSString?
        record["ruleSearchData"] = src.ruleSearchData as NSData?
        record["ruleBookInfoData"] = src.ruleBookInfoData as NSData?
        record["ruleTocData"] = src.ruleTocData as NSData?
        record["ruleContentData"] = src.ruleContentData as NSData?
        record["updatedAt"] = src.updatedAt as NSDate
        record["isDeleted"] = (src.isDeleted ? 1 : 0) as Int64 as NSNumber
        return record
    }

    static func bookSource(from record: CKRecord) -> SyncBookSourceRecord? {
        guard let sourceName = record["sourceName"] as? String,
              let sourceType = record["sourceType"] as? String,
              let updatedAt = record["updatedAt"] as? Date else {
            return nil
        }
        let enabled = ((record["enabled"] as? Int64) ?? 0) != 0
        let isDeleted = ((record["isDeleted"] as? Int64) ?? 0) != 0
        return SyncBookSourceRecord(
            sourceURL: record.recordID.recordName,
            sourceName: sourceName,
            sourceGroup: record["sourceGroup"] as? String,
            sourceType: sourceType,
            enabled: enabled,
            searchURL: record["searchURL"] as? String,
            ruleSearchData: record["ruleSearchData"] as? Data,
            ruleBookInfoData: record["ruleBookInfoData"] as? Data,
            ruleTocData: record["ruleTocData"] as? Data,
            ruleContentData: record["ruleContentData"] as? Data,
            updatedAt: updatedAt,
            isDeleted: isDeleted
        )
    }

    // MARK: - VRReplacementRule

    static func record(from rule: SyncReplacementRuleRecord, zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: rule.ruleId, zoneID: zoneID)
        let record = CKRecord(recordType: "VRReplacementRule", recordID: recordID)
        record["pattern"] = rule.pattern as NSString
        record["replacement"] = rule.replacement as NSString
        record["isRegex"] = (rule.isRegex ? 1 : 0) as Int64 as NSNumber
        record["scopeKey"] = rule.scopeKey as NSString?
        record["enabled"] = (rule.enabled ? 1 : 0) as Int64 as NSNumber
        record["order"] = Int64(rule.order) as NSNumber
        record["label"] = rule.label as NSString?
        record["createdAt"] = rule.createdAt as NSDate
        record["isDeleted"] = (rule.isDeleted ? 1 : 0) as Int64 as NSNumber
        return record
    }

    static func replacementRule(from record: CKRecord) -> SyncReplacementRuleRecord? {
        guard let pattern = record["pattern"] as? String,
              let replacement = record["replacement"] as? String,
              let createdAt = record["createdAt"] as? Date else {
            return nil
        }
        let isRegex = ((record["isRegex"] as? Int64) ?? 0) != 0
        let enabled = ((record["enabled"] as? Int64) ?? 0) != 0
        let isDeleted = ((record["isDeleted"] as? Int64) ?? 0) != 0
        let order = (record["order"] as? Int64).map { Int($0) } ?? 0
        return SyncReplacementRuleRecord(
            ruleId: record.recordID.recordName,
            pattern: pattern,
            replacement: replacement,
            isRegex: isRegex,
            scopeKey: record["scopeKey"] as? String,
            enabled: enabled,
            order: order,
            label: record["label"] as? String,
            createdAt: createdAt,
            isDeleted: isDeleted
        )
    }
}
