// Purpose: Tests for SourceSharingService — export/import single sources
// as Legado-compatible JSON, generate QR codes, parse URL schemes.
//
// @coordinates-with: SourceSharingService.swift, LegadoImporter.swift,
//   BookSource.swift, LegadoBookSourceDTO.swift

import Testing
import Foundation
#if canImport(CoreImage)
import CoreImage
#endif
@testable import vreader

@Suite("SourceSharingService")
struct SourceSharingServiceTests {

    // MARK: - Helpers

    /// Creates a BookSource for testing.
    private func makeBookSource(
        url: String = "https://example.com",
        name: String = "Test Source",
        searchURL: String? = "https://example.com/search?q={{key}}"
    ) -> BookSource {
        let source = BookSource(
            sourceURL: url,
            sourceName: name,
            searchURL: searchURL
        )
        source.updateTocRule(BSTocRule(
            chapterList: "div.chapter",
            chapterName: "a",
            chapterUrl: "a@href"
        ))
        return source
    }

    // MARK: - Export: Single Source → Valid JSON

    @Test("Export single source produces valid Legado-compatible JSON")
    func exportSingle_producesValidJSON() throws {
        let source = makeBookSource()

        let data = try SourceSharingService.exportSource(source)

        // Must be valid JSON
        let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        #expect(json != nil, "Should be a JSON array")
        #expect(json?.count == 1, "Should contain exactly one source")

        // Verify key fields
        let first = json?.first
        #expect(first?["bookSourceUrl"] as? String == "https://example.com")
        #expect(first?["bookSourceName"] as? String == "Test Source")
        #expect(first?["searchUrl"] as? String == "https://example.com/search?q={{key}}")
    }

    // MARK: - Import: Shared Source → Creates BookSource

    @Test("Import shared JSON data creates a BookSource")
    func importShared_createsSource() throws {
        let source = makeBookSource()
        let exported = try SourceSharingService.exportSource(source)

        let imported = try SourceSharingService.importSource(from: exported)

        #expect(imported.count == 1)
        #expect(imported.first?.sourceURL == "https://example.com")
        #expect(imported.first?.sourceName == "Test Source")
        #expect(imported.first?.ruleToc != nil)
    }

    // MARK: - Round-Trip: Export → Import Preserves Data

    @Test("Export then import preserves all fields")
    func exportImport_roundTrip() throws {
        let source = makeBookSource()
        let exported = try SourceSharingService.exportSource(source)
        let imported = try SourceSharingService.importSource(from: exported)

        #expect(imported.count == 1)
        let result = imported.first!
        #expect(result.sourceURL == source.sourceURL)
        #expect(result.sourceName == source.sourceName)
        #expect(result.searchURL == source.searchURL)
        #expect(result.ruleToc?.chapterList == "div.chapter")
        #expect(result.ruleToc?.chapterName == "a")
        #expect(result.ruleToc?.chapterUrl == "a@href")
    }

    // MARK: - URL Scheme: Parse Correctly

    @Test("URL scheme with base64 data parses correctly")
    func urlScheme_parsesCorrectly() throws {
        let source = makeBookSource()
        let exported = try SourceSharingService.exportSource(source)
        let base64 = exported.base64EncodedString()

        let urlString = "vreader://import-source?data=\(base64)"
        let url = URL(string: urlString)!

        let parsed = try SourceSharingService.parseImportURL(url)

        #expect(parsed.count == 1)
        #expect(parsed.first?.sourceURL == "https://example.com")
    }

    // MARK: - URL Scheme: Invalid URL

    @Test("Invalid URL scheme returns error")
    func urlScheme_invalidScheme_throwsError() throws {
        let url = URL(string: "https://other.com/import-source?data=abc")!

        #expect(throws: SourceSharingError.self) {
            try SourceSharingService.parseImportURL(url)
        }
    }

    // MARK: - URL Scheme: Missing Data Parameter

    @Test("URL scheme without data parameter throws error")
    func urlScheme_missingData_throwsError() throws {
        let url = URL(string: "vreader://import-source")!

        #expect(throws: SourceSharingError.self) {
            try SourceSharingService.parseImportURL(url)
        }
    }

    // MARK: - URL Scheme: Invalid Base64

    @Test("URL scheme with invalid base64 throws error")
    func urlScheme_invalidBase64_throwsError() throws {
        let url = URL(string: "vreader://import-source?data=!!!notbase64!!!")!

        #expect(throws: SourceSharingError.self) {
            try SourceSharingService.parseImportURL(url)
        }
    }

    // MARK: - QR Code: Generates Image Data

    @Test("QR code generation returns non-nil image data")
    func qrCode_generatesImage() throws {
        let source = makeBookSource(
            url: "https://example.com",
            name: "Tiny Source",
            searchURL: nil
        )
        let exported = try SourceSharingService.exportSource(source)
        let base64 = exported.base64EncodedString()
        let urlString = "vreader://import-source?data=\(base64)"

        let imageData = SourceSharingService.generateQRCode(for: urlString)

        #expect(imageData != nil, "QR code image data should not be nil")
        #expect(imageData!.count > 0, "QR code image data should not be empty")
    }

    // MARK: - Edge Case: Empty Source URL

    @Test("Export source with empty URL produces valid JSON")
    func exportSource_emptyURL_validJSON() throws {
        let source = makeBookSource(url: "", name: "Empty URL Source")

        let data = try SourceSharingService.exportSource(source)
        let json = try JSONSerialization.jsonObject(with: data)
        #expect(json is [[String: Any]])
    }

    // MARK: - Edge Case: CJK Source Name

    @Test("Export preserves CJK characters in source name")
    func exportSource_CJK_preserved() throws {
        let source = makeBookSource(url: "https://example.com", name: "笔趣阁小说网")

        let data = try SourceSharingService.exportSource(source)
        let imported = try SourceSharingService.importSource(from: data)

        #expect(imported.first?.sourceName == "笔趣阁小说网")
    }

    // MARK: - Edge Case: Import Invalid JSON

    @Test("Import invalid JSON throws error")
    func importSource_invalidJSON_throwsError() throws {
        let badData = "not json at all".data(using: .utf8)!

        #expect(throws: LegadoImportError.self) {
            try SourceSharingService.importSource(from: badData)
        }
    }

    // MARK: - Edge Case: Generate URL Scheme String

    @Test("Generate sharing URL returns well-formed vreader:// URL")
    func generateSharingURL_wellFormed() throws {
        let source = makeBookSource()

        let urlString = try SourceSharingService.generateSharingURL(for: source)

        #expect(urlString.hasPrefix("vreader://import-source?data="))

        // Should be parseable back
        let url = URL(string: urlString)!
        let parsed = try SourceSharingService.parseImportURL(url)
        #expect(parsed.first?.sourceURL == "https://example.com")
    }

    // MARK: - Edge Case: QR Code for Empty String

    @Test("QR code for empty string returns nil")
    func qrCode_emptyString_returnsNil() {
        let imageData = SourceSharingService.generateQRCode(for: "")
        #expect(imageData == nil)
    }
}
