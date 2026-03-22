// Purpose: Tests for CloudKitRecordMapper — bidirectional CKRecord mapping for all 8 sync types.
// Covers round-trip fidelity, nil handling, unknown fields ignored (forward compat),
// date precision, JSON blob Locator round-trip, Unicode/CJK strings, Boolean↔Int encoding.

import Testing
import Foundation
import CloudKit
@testable import vreader

// MARK: - Test Helpers

private let testZoneID = CKRecordZone.ID(
    zoneName: "VReaderData",
    ownerName: CKCurrentUserDefaultName
)

private let refDate = SyncTestHelpers.refDate
private let fpA = SyncTestHelpers.fingerprintA

private func date(offsetBy seconds: TimeInterval) -> Date {
    SyncTestHelpers.date(offsetBy: seconds)
}

/// Creates a Locator and encodes it to JSON Data for round-trip tests.
private func makeLocatorJSON(
    fingerprint: DocumentFingerprint = SyncTestHelpers.fingerprintA,
    charOffset: Int = 42
) -> String {
    let locator = SyncTestHelpers.makeLocator(fingerprint: fingerprint, charOffset: charOffset)
    let data = try! JSONEncoder().encode(locator)
    return String(data: data, encoding: .utf8)!
}

// MARK: - VRBook Round-Trip

@Suite("CloudKitRecordMapper — VRBook")
struct VRBookMapperTests {

    @Test func roundTrip() {
        let input = SyncBookRecord(
            fingerprintKey: fpA.canonicalKey,
            title: "Test Book",
            author: "Author Name",
            format: "epub",
            fileByteCount: 1024,
            addedAt: refDate,
            tags: ["fiction", "sci-fi"],
            isFavorite: true,
            detectedEncoding: "utf-8",
            updatedAt: date(offsetBy: 60)
        )
        let record = CloudKitRecordMapper.record(from: input, zoneID: testZoneID)
        #expect(record.recordType == "VRBook")
        #expect(record.recordID.recordName == fpA.canonicalKey)

        let output = CloudKitRecordMapper.book(from: record)
        #expect(output != nil)
        #expect(output?.fingerprintKey == input.fingerprintKey)
        #expect(output?.title == input.title)
        #expect(output?.author == input.author)
        #expect(output?.format == input.format)
        #expect(output?.fileByteCount == input.fileByteCount)
        #expect(output?.addedAt == input.addedAt)
        #expect(output?.tags == input.tags)
        #expect(output?.isFavorite == input.isFavorite)
        #expect(output?.detectedEncoding == input.detectedEncoding)
        #expect(output?.updatedAt == input.updatedAt)
    }

    @Test func nilOptionalFields() {
        let input = SyncBookRecord(
            fingerprintKey: fpA.canonicalKey,
            title: "Minimal",
            author: nil,
            format: "txt",
            fileByteCount: 0,
            addedAt: refDate,
            tags: [],
            isFavorite: false,
            detectedEncoding: nil,
            updatedAt: refDate
        )
        let record = CloudKitRecordMapper.record(from: input, zoneID: testZoneID)
        let output = CloudKitRecordMapper.book(from: record)
        #expect(output != nil)
        #expect(output?.author == nil)
        #expect(output?.detectedEncoding == nil)
        #expect(output?.tags == [])
        #expect(output?.isFavorite == false)
    }

    @Test func unicodeTitleAndAuthor() {
        let input = SyncBookRecord(
            fingerprintKey: fpA.canonicalKey,
            title: "三体 — The Three-Body Problem",
            author: "刘慈欣 (Liu Cixin)",
            format: "epub",
            fileByteCount: 2048,
            addedAt: refDate,
            tags: ["科幻", "中文"],
            isFavorite: false,
            detectedEncoding: nil,
            updatedAt: refDate
        )
        let record = CloudKitRecordMapper.record(from: input, zoneID: testZoneID)
        let output = CloudKitRecordMapper.book(from: record)
        #expect(output?.title == "三体 — The Three-Body Problem")
        #expect(output?.author == "刘慈欣 (Liu Cixin)")
        #expect(output?.tags == ["科幻", "中文"])
    }

    @Test func unknownFieldsIgnored() {
        let input = SyncBookRecord(
            fingerprintKey: fpA.canonicalKey,
            title: "Book",
            author: nil,
            format: "pdf",
            fileByteCount: 100,
            addedAt: refDate,
            tags: [],
            isFavorite: false,
            detectedEncoding: nil,
            updatedAt: refDate
        )
        let record = CloudKitRecordMapper.record(from: input, zoneID: testZoneID)
        // Simulate a future field added by a newer app version
        record["futureField"] = "unknown value"
        let output = CloudKitRecordMapper.book(from: record)
        #expect(output != nil)
        #expect(output?.title == "Book")
    }

    @Test func emptyTitle() {
        let input = SyncBookRecord(
            fingerprintKey: fpA.canonicalKey,
            title: "",
            author: nil,
            format: "txt",
            fileByteCount: 0,
            addedAt: refDate,
            tags: [],
            isFavorite: false,
            detectedEncoding: nil,
            updatedAt: refDate
        )
        let record = CloudKitRecordMapper.record(from: input, zoneID: testZoneID)
        let output = CloudKitRecordMapper.book(from: record)
        #expect(output?.title == "")
    }
}

// MARK: - VRReadingPosition Round-Trip

@Suite("CloudKitRecordMapper — VRReadingPosition")
struct VRReadingPositionMapperTests {

    @Test func roundTrip() {
        let locJSON = makeLocatorJSON()
        let input = SyncReadingPositionRecord(
            bookFingerprintKey: fpA.canonicalKey,
            locatorJSON: locJSON,
            updatedAt: date(offsetBy: 30),
            deviceId: SyncTestHelpers.deviceA
        )
        let record = CloudKitRecordMapper.record(from: input, zoneID: testZoneID)
        #expect(record.recordType == "VRReadingPosition")
        #expect(record.recordID.recordName == fpA.canonicalKey)

        let output = CloudKitRecordMapper.readingPosition(from: record)
        #expect(output != nil)
        #expect(output?.bookFingerprintKey == input.bookFingerprintKey)
        #expect(output?.locatorJSON == input.locatorJSON)
        #expect(output?.updatedAt == input.updatedAt)
        #expect(output?.deviceId == input.deviceId)
    }

    @Test func locatorJSONRoundTrip() {
        let locator = SyncTestHelpers.makeLocator(charOffset: 999)
        let data = try! JSONEncoder().encode(locator)
        let json = String(data: data, encoding: .utf8)!

        let input = SyncReadingPositionRecord(
            bookFingerprintKey: fpA.canonicalKey,
            locatorJSON: json,
            updatedAt: refDate,
            deviceId: "dev-1"
        )
        let record = CloudKitRecordMapper.record(from: input, zoneID: testZoneID)
        let output = CloudKitRecordMapper.readingPosition(from: record)

        // Decode back to Locator to verify
        let decodedLocator = try! JSONDecoder().decode(Locator.self, from: output!.locatorJSON.data(using: .utf8)!)
        #expect(decodedLocator.charOffsetUTF16 == 999)
    }

    @Test func datePrecisionPreserved() {
        let preciseDate = Date(timeIntervalSinceReferenceDate: 700_000_000.123456)
        let input = SyncReadingPositionRecord(
            bookFingerprintKey: fpA.canonicalKey,
            locatorJSON: "{}",
            updatedAt: preciseDate,
            deviceId: "dev"
        )
        let record = CloudKitRecordMapper.record(from: input, zoneID: testZoneID)
        let output = CloudKitRecordMapper.readingPosition(from: record)
        // CKRecord stores Date as NSDate with subsecond precision
        #expect(abs(output!.updatedAt.timeIntervalSinceReferenceDate - preciseDate.timeIntervalSinceReferenceDate) < 0.001)
    }
}

// MARK: - VRBookmark Round-Trip

@Suite("CloudKitRecordMapper — VRBookmark")
struct VRBookmarkMapperTests {

    @Test func roundTrip() {
        let locJSON = makeLocatorJSON()
        let input = SyncCKBookmarkRecord(
            bookmarkId: "bm-001",
            bookFingerprintKey: fpA.canonicalKey,
            locatorJSON: locJSON,
            title: "Chapter 1",
            createdAt: refDate,
            updatedAt: date(offsetBy: 120),
            isDeleted: false
        )
        let record = CloudKitRecordMapper.record(from: input, zoneID: testZoneID)
        #expect(record.recordType == "VRBookmark")
        #expect(record.recordID.recordName == "bm-001")

        let output = CloudKitRecordMapper.bookmark(from: record)
        #expect(output != nil)
        #expect(output?.bookmarkId == input.bookmarkId)
        #expect(output?.bookFingerprintKey == input.bookFingerprintKey)
        #expect(output?.locatorJSON == input.locatorJSON)
        #expect(output?.title == input.title)
        #expect(output?.createdAt == input.createdAt)
        #expect(output?.updatedAt == input.updatedAt)
        #expect(output?.isDeleted == false)
    }

    @Test func deletedBookmark() {
        let input = SyncCKBookmarkRecord(
            bookmarkId: "bm-del",
            bookFingerprintKey: fpA.canonicalKey,
            locatorJSON: "{}",
            title: nil,
            createdAt: refDate,
            updatedAt: refDate,
            isDeleted: true
        )
        let record = CloudKitRecordMapper.record(from: input, zoneID: testZoneID)
        // isDeleted stored as Int 0/1
        #expect(record["isDeleted"] as? Int64 == 1)

        let output = CloudKitRecordMapper.bookmark(from: record)
        #expect(output?.isDeleted == true)
        #expect(output?.title == nil)
    }

    @Test func nilTitle() {
        let input = SyncCKBookmarkRecord(
            bookmarkId: "bm-notitle",
            bookFingerprintKey: fpA.canonicalKey,
            locatorJSON: "{}",
            title: nil,
            createdAt: refDate,
            updatedAt: refDate,
            isDeleted: false
        )
        let record = CloudKitRecordMapper.record(from: input, zoneID: testZoneID)
        let output = CloudKitRecordMapper.bookmark(from: record)
        #expect(output?.title == nil)
    }
}

// MARK: - VRHighlight Round-Trip

@Suite("CloudKitRecordMapper — VRHighlight")
struct VRHighlightMapperTests {

    @Test func roundTrip() {
        let locJSON = makeLocatorJSON()
        let input = SyncCKHighlightRecord(
            highlightId: "hl-001",
            bookFingerprintKey: fpA.canonicalKey,
            locatorJSON: locJSON,
            selectedText: "highlighted text here",
            color: "yellow",
            note: "My note",
            createdAt: refDate,
            updatedAt: date(offsetBy: 200),
            isDeleted: false
        )
        let record = CloudKitRecordMapper.record(from: input, zoneID: testZoneID)
        #expect(record.recordType == "VRHighlight")
        #expect(record.recordID.recordName == "hl-001")

        let output = CloudKitRecordMapper.highlight(from: record)
        #expect(output != nil)
        #expect(output?.highlightId == input.highlightId)
        #expect(output?.bookFingerprintKey == input.bookFingerprintKey)
        #expect(output?.selectedText == input.selectedText)
        #expect(output?.color == input.color)
        #expect(output?.note == input.note)
        #expect(output?.isDeleted == false)
    }

    @Test func nilNote() {
        let input = SyncCKHighlightRecord(
            highlightId: "hl-nonote",
            bookFingerprintKey: fpA.canonicalKey,
            locatorJSON: "{}",
            selectedText: "text",
            color: "blue",
            note: nil,
            createdAt: refDate,
            updatedAt: refDate,
            isDeleted: false
        )
        let record = CloudKitRecordMapper.record(from: input, zoneID: testZoneID)
        let output = CloudKitRecordMapper.highlight(from: record)
        #expect(output?.note == nil)
    }

    @Test func unicodeSelectedText() {
        let input = SyncCKHighlightRecord(
            highlightId: "hl-cjk",
            bookFingerprintKey: fpA.canonicalKey,
            locatorJSON: "{}",
            selectedText: "这是一段中文高亮文本 🌟",
            color: "green",
            note: "注释 — note with émojis 😊",
            createdAt: refDate,
            updatedAt: refDate,
            isDeleted: false
        )
        let record = CloudKitRecordMapper.record(from: input, zoneID: testZoneID)
        let output = CloudKitRecordMapper.highlight(from: record)
        #expect(output?.selectedText == "这是一段中文高亮文本 🌟")
        #expect(output?.note == "注释 — note with émojis 😊")
    }

    @Test func deletedHighlight() {
        let input = SyncCKHighlightRecord(
            highlightId: "hl-del",
            bookFingerprintKey: fpA.canonicalKey,
            locatorJSON: "{}",
            selectedText: "",
            color: "yellow",
            note: nil,
            createdAt: refDate,
            updatedAt: refDate,
            isDeleted: true
        )
        let record = CloudKitRecordMapper.record(from: input, zoneID: testZoneID)
        #expect(record["isDeleted"] as? Int64 == 1)
        let output = CloudKitRecordMapper.highlight(from: record)
        #expect(output?.isDeleted == true)
    }
}

// MARK: - VRAnnotation Round-Trip

@Suite("CloudKitRecordMapper — VRAnnotation")
struct VRAnnotationMapperTests {

    @Test func roundTrip() {
        let locJSON = makeLocatorJSON()
        let input = SyncCKAnnotationRecord(
            annotationId: "an-001",
            bookFingerprintKey: fpA.canonicalKey,
            locatorJSON: locJSON,
            content: "This is my annotation content.",
            createdAt: refDate,
            updatedAt: date(offsetBy: 300),
            isDeleted: false
        )
        let record = CloudKitRecordMapper.record(from: input, zoneID: testZoneID)
        #expect(record.recordType == "VRAnnotation")
        #expect(record.recordID.recordName == "an-001")

        let output = CloudKitRecordMapper.annotation(from: record)
        #expect(output != nil)
        #expect(output?.annotationId == input.annotationId)
        #expect(output?.content == input.content)
        #expect(output?.isDeleted == false)
    }

    @Test func deletedAnnotation() {
        let input = SyncCKAnnotationRecord(
            annotationId: "an-del",
            bookFingerprintKey: fpA.canonicalKey,
            locatorJSON: "{}",
            content: "",
            createdAt: refDate,
            updatedAt: refDate,
            isDeleted: true
        )
        let record = CloudKitRecordMapper.record(from: input, zoneID: testZoneID)
        let output = CloudKitRecordMapper.annotation(from: record)
        #expect(output?.isDeleted == true)
    }

    @Test func emptyContent() {
        let input = SyncCKAnnotationRecord(
            annotationId: "an-empty",
            bookFingerprintKey: fpA.canonicalKey,
            locatorJSON: "{}",
            content: "",
            createdAt: refDate,
            updatedAt: refDate,
            isDeleted: false
        )
        let record = CloudKitRecordMapper.record(from: input, zoneID: testZoneID)
        let output = CloudKitRecordMapper.annotation(from: record)
        #expect(output?.content == "")
    }
}

// MARK: - VRReadingSession Round-Trip

@Suite("CloudKitRecordMapper — VRReadingSession")
struct VRReadingSessionMapperTests {

    @Test func roundTrip() {
        let input = SyncReadingSessionRecord(
            sessionId: "sess-001",
            bookFingerprintKey: fpA.canonicalKey,
            startedAt: refDate,
            endedAt: date(offsetBy: 600),
            durationSeconds: 600,
            pagesRead: 10,
            wordsRead: 2500,
            deviceId: SyncTestHelpers.deviceA,
            isRecovered: false
        )
        let record = CloudKitRecordMapper.record(from: input, zoneID: testZoneID)
        #expect(record.recordType == "VRReadingSession")
        #expect(record.recordID.recordName == "sess-001")

        let output = CloudKitRecordMapper.readingSession(from: record)
        #expect(output != nil)
        #expect(output?.sessionId == input.sessionId)
        #expect(output?.bookFingerprintKey == input.bookFingerprintKey)
        #expect(output?.startedAt == input.startedAt)
        #expect(output?.endedAt == input.endedAt)
        #expect(output?.durationSeconds == 600)
        #expect(output?.pagesRead == 10)
        #expect(output?.wordsRead == 2500)
        #expect(output?.deviceId == SyncTestHelpers.deviceA)
        #expect(output?.isRecovered == false)
    }

    @Test func nilOptionalFields() {
        let input = SyncReadingSessionRecord(
            sessionId: "sess-min",
            bookFingerprintKey: fpA.canonicalKey,
            startedAt: refDate,
            endedAt: nil,
            durationSeconds: 0,
            pagesRead: nil,
            wordsRead: nil,
            deviceId: "dev",
            isRecovered: false
        )
        let record = CloudKitRecordMapper.record(from: input, zoneID: testZoneID)
        let output = CloudKitRecordMapper.readingSession(from: record)
        #expect(output?.endedAt == nil)
        #expect(output?.pagesRead == nil)
        #expect(output?.wordsRead == nil)
    }

    @Test func recoveredSession() {
        let input = SyncReadingSessionRecord(
            sessionId: "sess-rec",
            bookFingerprintKey: fpA.canonicalKey,
            startedAt: refDate,
            endedAt: refDate,
            durationSeconds: 120,
            pagesRead: nil,
            wordsRead: nil,
            deviceId: "dev",
            isRecovered: true
        )
        let record = CloudKitRecordMapper.record(from: input, zoneID: testZoneID)
        #expect(record["isRecovered"] as? Int64 == 1)
        let output = CloudKitRecordMapper.readingSession(from: record)
        #expect(output?.isRecovered == true)
    }
}

// MARK: - VRBookSource Round-Trip

@Suite("CloudKitRecordMapper — VRBookSource")
struct VRBookSourceMapperTests {

    @Test func roundTrip() {
        let ruleData = Data("search-rule-json".utf8)
        let infoData = Data("info-rule-json".utf8)
        let tocData = Data("toc-rule-json".utf8)
        let contentData = Data("content-rule-json".utf8)

        let input = SyncBookSourceRecord(
            sourceURL: "https://example.com/source",
            sourceName: "Example Source",
            sourceGroup: "Group A",
            sourceType: "web",
            enabled: true,
            searchURL: "https://example.com/search?q=",
            ruleSearchData: ruleData,
            ruleBookInfoData: infoData,
            ruleTocData: tocData,
            ruleContentData: contentData,
            updatedAt: date(offsetBy: 500),
            isDeleted: false
        )
        let record = CloudKitRecordMapper.record(from: input, zoneID: testZoneID)
        #expect(record.recordType == "VRBookSource")
        #expect(record.recordID.recordName == "https://example.com/source")

        let output = CloudKitRecordMapper.bookSource(from: record)
        #expect(output != nil)
        #expect(output?.sourceURL == input.sourceURL)
        #expect(output?.sourceName == input.sourceName)
        #expect(output?.sourceGroup == input.sourceGroup)
        #expect(output?.sourceType == input.sourceType)
        #expect(output?.enabled == true)
        #expect(output?.searchURL == input.searchURL)
        #expect(output?.ruleSearchData == ruleData)
        #expect(output?.ruleBookInfoData == infoData)
        #expect(output?.ruleTocData == tocData)
        #expect(output?.ruleContentData == contentData)
        #expect(output?.isDeleted == false)
    }

    @Test func nilOptionalFields() {
        let input = SyncBookSourceRecord(
            sourceURL: "https://min.com",
            sourceName: "Min",
            sourceGroup: nil,
            sourceType: "web",
            enabled: false,
            searchURL: nil,
            ruleSearchData: nil,
            ruleBookInfoData: nil,
            ruleTocData: nil,
            ruleContentData: nil,
            updatedAt: refDate,
            isDeleted: false
        )
        let record = CloudKitRecordMapper.record(from: input, zoneID: testZoneID)
        let output = CloudKitRecordMapper.bookSource(from: record)
        #expect(output != nil)
        #expect(output?.sourceGroup == nil)
        #expect(output?.searchURL == nil)
        #expect(output?.ruleSearchData == nil)
        #expect(output?.enabled == false)
    }

    @Test func deletedSource() {
        let input = SyncBookSourceRecord(
            sourceURL: "https://deleted.com",
            sourceName: "Deleted",
            sourceGroup: nil,
            sourceType: "web",
            enabled: false,
            searchURL: nil,
            ruleSearchData: nil,
            ruleBookInfoData: nil,
            ruleTocData: nil,
            ruleContentData: nil,
            updatedAt: refDate,
            isDeleted: true
        )
        let record = CloudKitRecordMapper.record(from: input, zoneID: testZoneID)
        #expect(record["isDeleted"] as? Int64 == 1)
        let output = CloudKitRecordMapper.bookSource(from: record)
        #expect(output?.isDeleted == true)
    }
}

// MARK: - VRReplacementRule Round-Trip

@Suite("CloudKitRecordMapper — VRReplacementRule")
struct VRReplacementRuleMapperTests {

    @Test func roundTrip() {
        let input = SyncReplacementRuleRecord(
            ruleId: "rule-001",
            pattern: "\\bfoo\\b",
            replacement: "bar",
            isRegex: true,
            scopeKey: fpA.canonicalKey,
            enabled: true,
            order: 5,
            label: "Replace foo with bar",
            createdAt: refDate,
            isDeleted: false
        )
        let record = CloudKitRecordMapper.record(from: input, zoneID: testZoneID)
        #expect(record.recordType == "VRReplacementRule")
        #expect(record.recordID.recordName == "rule-001")

        let output = CloudKitRecordMapper.replacementRule(from: record)
        #expect(output != nil)
        #expect(output?.ruleId == input.ruleId)
        #expect(output?.pattern == input.pattern)
        #expect(output?.replacement == input.replacement)
        #expect(output?.isRegex == true)
        #expect(output?.scopeKey == fpA.canonicalKey)
        #expect(output?.enabled == true)
        #expect(output?.order == 5)
        #expect(output?.label == "Replace foo with bar")
        #expect(output?.isDeleted == false)
    }

    @Test func nilOptionalFields() {
        let input = SyncReplacementRuleRecord(
            ruleId: "rule-min",
            pattern: "a",
            replacement: "b",
            isRegex: false,
            scopeKey: nil,
            enabled: true,
            order: 0,
            label: nil,
            createdAt: refDate,
            isDeleted: false
        )
        let record = CloudKitRecordMapper.record(from: input, zoneID: testZoneID)
        let output = CloudKitRecordMapper.replacementRule(from: record)
        #expect(output != nil)
        #expect(output?.scopeKey == nil)
        #expect(output?.label == nil)
        #expect(output?.isRegex == false)
    }

    @Test func deletedRule() {
        let input = SyncReplacementRuleRecord(
            ruleId: "rule-del",
            pattern: "x",
            replacement: "y",
            isRegex: false,
            scopeKey: nil,
            enabled: false,
            order: 0,
            label: nil,
            createdAt: refDate,
            isDeleted: true
        )
        let record = CloudKitRecordMapper.record(from: input, zoneID: testZoneID)
        #expect(record["isDeleted"] as? Int64 == 1)
        let output = CloudKitRecordMapper.replacementRule(from: record)
        #expect(output?.isDeleted == true)
        #expect(output?.enabled == false)
    }

    @Test func unicodePatternAndReplacement() {
        let input = SyncReplacementRuleRecord(
            ruleId: "rule-cjk",
            pattern: "简体",
            replacement: "繁體",
            isRegex: false,
            scopeKey: nil,
            enabled: true,
            order: 1,
            label: "简繁转换",
            createdAt: refDate,
            isDeleted: false
        )
        let record = CloudKitRecordMapper.record(from: input, zoneID: testZoneID)
        let output = CloudKitRecordMapper.replacementRule(from: record)
        #expect(output?.pattern == "简体")
        #expect(output?.replacement == "繁體")
        #expect(output?.label == "简繁转换")
    }
}

// MARK: - Cross-Cutting: Missing Required Fields

@Suite("CloudKitRecordMapper — Missing Required Fields")
struct CloudKitRecordMapperMissingFieldTests {

    @Test func bookMissingTitleReturnsNil() {
        let recordID = CKRecord.ID(recordName: "test", zoneID: testZoneID)
        let record = CKRecord(recordType: "VRBook", recordID: recordID)
        // Missing title field
        record["format"] = "epub"
        record["fileByteCount"] = 100 as Int64
        record["addedAt"] = refDate as NSDate
        record["isFavorite"] = 0 as Int64
        record["updatedAt"] = refDate as NSDate
        let output = CloudKitRecordMapper.book(from: record)
        #expect(output == nil)
    }

    @Test func readingPositionMissingLocatorJSONReturnsNil() {
        let recordID = CKRecord.ID(recordName: "test-pos", zoneID: testZoneID)
        let record = CKRecord(recordType: "VRReadingPosition", recordID: recordID)
        record["updatedAt"] = refDate as NSDate
        record["deviceId"] = "dev"
        // Missing locatorJSON
        let output = CloudKitRecordMapper.readingPosition(from: record)
        #expect(output == nil)
    }

    @Test func bookmarkMissingBookFingerprintKeyReturnsNil() {
        let recordID = CKRecord.ID(recordName: "bm-bad", zoneID: testZoneID)
        let record = CKRecord(recordType: "VRBookmark", recordID: recordID)
        record["locatorJSON"] = "{}"
        record["createdAt"] = refDate as NSDate
        record["updatedAt"] = refDate as NSDate
        record["isDeleted"] = 0 as Int64
        // Missing bookFingerprintKey
        let output = CloudKitRecordMapper.bookmark(from: record)
        #expect(output == nil)
    }
}

// MARK: - Boolean ↔ Int Encoding

@Suite("CloudKitRecordMapper — Boolean Encoding")
struct BooleanEncodingTests {

    @Test func boolTrueEncodesAsOne() {
        let input = SyncBookRecord(
            fingerprintKey: fpA.canonicalKey,
            title: "T",
            author: nil,
            format: "txt",
            fileByteCount: 0,
            addedAt: refDate,
            tags: [],
            isFavorite: true,
            detectedEncoding: nil,
            updatedAt: refDate
        )
        let record = CloudKitRecordMapper.record(from: input, zoneID: testZoneID)
        #expect(record["isFavorite"] as? Int64 == 1)
    }

    @Test func boolFalseEncodesAsZero() {
        let input = SyncBookRecord(
            fingerprintKey: fpA.canonicalKey,
            title: "T",
            author: nil,
            format: "txt",
            fileByteCount: 0,
            addedAt: refDate,
            tags: [],
            isFavorite: false,
            detectedEncoding: nil,
            updatedAt: refDate
        )
        let record = CloudKitRecordMapper.record(from: input, zoneID: testZoneID)
        #expect(record["isFavorite"] as? Int64 == 0)
    }
}
